defmodule AshClickhouse.TypedJsonTest do
  use AshClickhouse.RepoCase, async: true

  alias AshClickhouse.MigrationGenerator
  alias AshClickhouse.Test.Resource.Pageview
  alias AshClickhouse.Test.Resource.Types.Visitor
  alias AshClickhouse.Test.Resource.Types.Visitor.User

  setup do
    TestRepo.query!("TRUNCATE TABLE pageviews")
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
end
