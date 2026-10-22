defmodule AshClickhouse.TypedJsonTest do
  use AshClickhouse.RepoCase, async: true

  alias AshClickhouse.MigrationGenerator
  alias AshClickhouse.Test.Resource.Pageview

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

  test "a typed JSON column is written and read back as plain JSON" do
    create!("example.com", %{user: %{id: "u1", visits: 1}})

    create!("example.com", %{
      "user" => %{"id" => "u2", "visits" => 3},
      "referrer" => "search"
    })

    assert [
             %Pageview{visitor: %{"user" => %{"id" => "u1", "visits" => 1}}},
             %Pageview{
               visitor: %{"user" => %{"id" => "u2", "visits" => 3}, "referrer" => "search"}
             }
           ] = Pageview |> Ash.Query.sort(:at) |> Ash.read!()
  end

  test "typed paths are stored with their types, and the rows sorted by them" do
    create!("example.com", %{"user" => %{"id" => "u2", "visits" => 3}})
    create!("example.com", %{"user" => %{"id" => "u1", "visits" => 1}})

    assert %{rows: [["u1", "String", "UInt32"], ["u2", "String", "UInt32"]]} =
             TestRepo.query!("""
             SELECT visitor.user.id, toTypeName(visitor.user.id), toTypeName(visitor.user.visits)
             FROM pageviews
             ORDER BY site, visitor.user.id, at
             """)
  end
end
