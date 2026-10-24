defmodule AshClickhouse.TypedJsonTest do
  use AshClickhouse.RepoCase, async: true

  alias AshClickhouse.MigrationGenerator
  alias AshClickhouse.Test.Resource.Contact
  alias AshClickhouse.Test.Resource.Pageview
  alias AshClickhouse.Test.Resource.Referral
  alias AshClickhouse.Test.Resource.Types.Visitor
  alias AshClickhouse.Test.Resource.Types.Visitor.User
  alias AshClickhouse.Type.ChJSON

  require Ash.Query

  setup do
    TestRepo.query!("TRUNCATE TABLE pageviews")
    TestRepo.query!("TRUNCATE TABLE referrals")
    TestRepo.query!("TRUNCATE TABLE contacts")
    :ok
  end

  defp create!(site, visitor) do
    Pageview
    |> Ash.Changeset.for_create(:create, %{site: site, visitor: visitor, at: DateTime.utc_now()})
    |> Ash.create!()
  end

  test "the generator's column type is the one ClickHouse reports for the migrated column" do
    %{"columns" => columns} = MigrationGenerator.snapshot(Pageview)

    assert %{rows: [[type]]} =
             TestRepo.query!(
               "SELECT type FROM system.columns WHERE database = currentDatabase() AND table = 'pageviews' AND name = 'visitor'"
             )

    assert %{"type" => ^type} = Enum.find(columns, &(&1["name"] == "visitor"))

    assert %{rows: [["site, visitor.user.id, at"]]} =
             TestRepo.query!(
               "SELECT sorting_key FROM system.tables WHERE database = currentDatabase() AND name = 'pageviews'"
             )
  end

  test "a typed struct is written and read back whole, nils and untyped fields included" do
    create!("example.com", %{user: %{id: "u1", visits: 1}})
    create!("example.com", %{user: %{id: "u2", visits: 3, plan: "pro"}, referrer: "search"})

    assert [
             %Pageview{
               visitor: %Visitor{user: %User{id: "u1", visits: 1, plan: nil}, referrer: nil}
             },
             %Pageview{
               visitor: %Visitor{
                 user: %User{id: "u2", visits: 3, plan: "pro"},
                 referrer: "search"
               }
             }
           ] = Pageview |> Ash.Query.sort(:at) |> Ash.read!()
  end

  test "typed paths are stored with their types, and the rows sorted by them" do
    create!("example.com", %{user: %{id: "u2", visits: 3}})
    create!("example.com", %{user: %{id: "u1", visits: 1}})

    assert %{
             rows: [
               ["u1", "String", "UInt32", "Nullable(String)"],
               ["u2", "String", "UInt32", "Nullable(String)"]
             ]
           } =
             TestRepo.query!("""
             SELECT visitor.user.id, toTypeName(visitor.user.id), toTypeName(visitor.user.visits),
               toTypeName(visitor.user.plan)
             FROM pageviews
             ORDER BY site, visitor.user.id, at
             """)
  end

  test "a union reads back each member it wrote, without the paths only the others type" do
    for value <- [%{url: "https://example.com"}, %{code: "autumn"}] do
      Referral
      |> Ash.Changeset.for_create(:create, %{origin: value, at: DateTime.utc_now()})
      |> Ash.create!()
    end

    assert [
             %Referral{origin: %Ash.Union{type: :link, value: link}},
             %Referral{origin: %Ash.Union{type: :campaign, value: campaign}}
           ] = Referral |> Ash.Query.sort(:at) |> Ash.read!()

    assert link == %{url: "https://example.com"}
    assert campaign == %{code: "autumn"}
  end

  test "a union tagged inside its members' maps reads back each member it wrote" do
    for value <- [
          %{kind: "email", address: "a@example.com"},
          %{kind: "web", url: "https://example.com"}
        ] do
      Contact
      |> Ash.Changeset.for_create(:create, %{channel: value, at: DateTime.utc_now()})
      |> Ash.create!()
    end

    assert [
             %Contact{channel: %Ash.Union{type: :email, value: email}},
             %Contact{channel: %Ash.Union{type: :web, value: web}}
           ] = Contact |> Ash.Query.sort(:at) |> Ash.read!()

    assert email == %{kind: "email", address: "a@example.com"}
    assert web == %{kind: "web", url: "https://example.com"}
  end

  test "a typed column is migrated in place both ways, keeping its rows" do
    old_type = "JSON(`user.id` String)"
    {:parameterized, {Ch, new_type}} = ChJSON.storage_type_of(Visitor)

    snapshot = fn type ->
      %{
        "typed_json_retype" => %{
          "table" => "typed_json_retype",
          "engine" => "MergeTree()",
          "options" => "order by id",
          "materialized_view" => nil,
          "columns" => [%{"name" => "id", "type" => "UInt8"}, %{"name" => "j", "type" => type}]
        }
      }
    end

    {up, down} =
      MigrationGenerator.statements(snapshot.(new_type), snapshot.(old_type), MapSet.new())

    assert up == ["ALTER TABLE typed_json_retype MODIFY COLUMN j #{new_type}"]
    assert down == ["ALTER TABLE typed_json_retype MODIFY COLUMN j #{old_type}"]

    on_exit(fn -> TestRepo.query!("DROP TABLE IF EXISTS typed_json_retype") end)

    TestRepo.query!(
      "CREATE TABLE typed_json_retype (id UInt8, j #{old_type}) ENGINE = MergeTree() ORDER BY id"
    )

    TestRepo.query!(
      ~s|INSERT INTO typed_json_retype VALUES (1, '{"user": {"id": "u1", "visits": 2}}')|
    )

    for {statements, type} <- [{up, new_type}, {down, old_type}] do
      Enum.each(statements, &TestRepo.query!(&1 <> " SETTINGS mutations_sync = 1"))

      assert %{rows: [[^type, "u1"]]} =
               TestRepo.query!("SELECT toTypeName(j), toString(j.user.id) FROM typed_json_retype")
    end
  end

  describe "path expressions" do
    setup do
      create!("example.com", %{user: %{id: "u1", visits: 1, plan: "pro"}, referrer: "search"})
      create!("example.com", %{user: %{id: "u2", visits: 3}})
      :ok
    end

    test "filter on a typed path" do
      assert [%Pageview{visitor: %Visitor{user: %User{id: "u1"}}}] =
               Pageview |> Ash.Query.filter(visitor[:user][:id] == "u1") |> Ash.read!()
    end

    test "compare a typed number as a number" do
      assert [%Pageview{visitor: %Visitor{user: %User{id: "u2"}}}] =
               Pageview |> Ash.Query.filter(visitor[:user][:visits] > 2) |> Ash.read!()
    end

    test "filter on a dynamic path" do
      assert [%Pageview{visitor: %Visitor{referrer: "search"}}] =
               Pageview |> Ash.Query.filter(visitor[:referrer] == "search") |> Ash.read!()
    end

    test "read a nullable typed path as nil where the field was nil" do
      assert [%Pageview{visitor: %Visitor{user: %User{id: "u2", plan: nil}}}] =
               Pageview |> Ash.Query.filter(is_nil(visitor[:user][:plan])) |> Ash.read!()
    end

    test "reach a union's members under value" do
      for value <- [%{url: "https://example.com"}, %{code: "autumn"}] do
        Referral
        |> Ash.Changeset.for_create(:create, %{origin: value, at: DateTime.utc_now()})
        |> Ash.create!()
      end

      assert [%Referral{origin: %Ash.Union{type: :link, value: %{url: "https://example.com"}}}] =
               Referral
               |> Ash.Query.filter(origin[:value][:url] == "https://example.com")
               |> Ash.read!()

      assert [%Referral{origin: %Ash.Union{type: :campaign, value: %{code: "autumn"}}}] =
               Referral |> Ash.Query.filter(origin[:value][:code] == "autumn") |> Ash.read!()
    end

    test "read a key with dots as the nested path it spells, as ClickHouse stores it" do
      assert [%Pageview{visitor: %Visitor{user: %User{id: "u1"}}}] =
               Pageview |> Ash.Query.filter(get_path(visitor, ["user.id"]) == "u1") |> Ash.read!()
    end

    test "refuse an array position, which a JSON path cannot name" do
      assert_raise Ash.Error.Unknown, ~r/a ClickHouse JSON path names object keys only/, fn ->
        Pageview |> Ash.Query.filter(get_path(visitor, [:user, 0]) == "u1") |> Ash.read!()
      end
    end
  end
end
