defmodule AshClickhouse.MaterializedViewTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias AshClickhouse.MaterializedView

  describe "select_sql/3" do
    test "an Ecto.Query is rendered against the source it is given" do
      query = fn source ->
        from(e in source,
          group_by: selected_as(:day),
          select: %{
            day: selected_as(fragment("toDate(?)", e.at), :day),
            events: selected_as(count(), :events)
          }
        )
      end

      assert {sql, ["day", "events"]} = MaterializedView.select_sql("events", query, nil)

      assert sql ==
               ~s|SELECT toDate(e0."at") AS "day",count(*) AS "events" FROM "events" AS e0 GROUP BY "day"|
    end

    test "a literal in the query is written into the SQL rather than bound" do
      query = fn source ->
        from(e in source, where: e.amount > 5, select: %{n: selected_as(e.name, :n)})
      end

      assert {sql, ["n"]} = MaterializedView.select_sql("events", query, nil)
      assert sql =~ ~s|WHERE (e0."amount" > 5)|
    end

    test "a pinned parameter is refused, because a view's SELECT is DDL" do
      cutoff = 5

      query = fn source ->
        from(e in source, where: e.amount > ^cutoff, select: %{n: selected_as(e.name, :n)})
      end

      assert_raise RuntimeError, ~r/carries 1 bound parameter/, fn ->
        MaterializedView.select_sql("events", query, nil)
      end
    end

    test "raw SQL passes through unparsed, so it reports no aliases" do
      assert {"SELECT 1 AS x FROM events", []} =
               MaterializedView.select_sql("events", nil, "SELECT 1 AS x FROM events")
    end

    test "an unaliased column reports no alias for itself" do
      query = fn source -> from(e in source, select: %{n: e.name}) end

      assert {_sql, []} = MaterializedView.select_sql("events", query, nil)
    end
  end

  describe "validate_aliases!/3" do
    test "aliases the destination has are accepted" do
      assert :ok = MaterializedView.validate_aliases!("mv", ["day", "events"], ["day", "events"])
    end

    test "a destination column the view skips is left to its default" do
      assert :ok = MaterializedView.validate_aliases!("mv", ["day"], ["day", "events"])
    end

    test "an alias the destination does not have is refused" do
      assert_raise RuntimeError, ~r/`evnets`.*does not have/s, fn ->
        MaterializedView.validate_aliases!("mv", ["day", "evnets"], ["day", "events"])
      end
    end

    test "raw SQL reports no aliases, so nothing is checked" do
      assert :ok = MaterializedView.validate_aliases!("mv", [], ["day", "events"])
    end
  end
end
