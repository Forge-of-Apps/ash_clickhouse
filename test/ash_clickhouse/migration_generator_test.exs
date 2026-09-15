defmodule AshClickhouse.MigrationGeneratorTest do
  use ExUnit.Case, async: true

  alias AshClickhouse.MigrationGenerator
  alias AshClickhouse.Test.Migration.Event
  alias AshClickhouse.Test.Migration.EventCount
  alias AshClickhouse.Test.Migration.EventsByDayMv
  alias AshClickhouse.Test.Migration.RawSelect

  defp snapshot(columns, overrides \\ %{}) do
    Map.merge(
      %{
        "table" => "events",
        "engine" => "MergeTree()",
        "options" => "order by id",
        "materialized_view" => nil,
        "columns" => Enum.map(columns, fn {name, type} -> %{"name" => name, "type" => type} end)
      },
      overrides
    )
  end

  defp view(overrides \\ %{}) do
    snapshot([{"day", "Date"}, {"events", "UInt64"}], %{
      "table" => "events_by_day_mv",
      "materialized_view" =>
        Map.merge(
          %{"source" => "events", "to" => "events_by_day", "select" => "SELECT 1"},
          overrides
        )
    })
  end

  describe "snapshot/1" do
    test "reads the table, engine, options and column types off the resource" do
      assert %{
               "table" => "events",
               "engine" => "MergeTree()",
               "options" => "order by id",
               "materialized_view" => nil,
               "columns" => [
                 %{"name" => "id", "type" => "UUID"},
                 %{"name" => "name", "type" => "String"},
                 %{"name" => "amount", "type" => "UInt32"},
                 %{"name" => "at", "type" => "DateTime64(6)"}
               ]
             } = MigrationGenerator.snapshot(Event)
    end

    test "a view records its source, destination and the SELECT its query rendered" do
      assert %{
               "materialized_view" => %{
                 "source" => "events",
                 "to" => "events_by_day",
                 "select" => select
               }
             } = MigrationGenerator.snapshot(EventsByDayMv)

      assert select =~ ~s|AS "day"|
      assert select =~ ~s|FROM "events"|
    end

    test "a view owning its storage keeps its engine and has no destination" do
      assert %{
               "engine" => "SummingMergeTree()",
               "options" => "order by name",
               "materialized_view" => %{"to" => nil}
             } = MigrationGenerator.snapshot(EventCount)
    end

    test "a raw select is recorded as written" do
      assert %{"materialized_view" => %{"select" => select}} =
               MigrationGenerator.snapshot(RawSelect)

      assert select == "SELECT toDate(at) AS day, count() AS events FROM events GROUP BY day"
    end

    test "round-trips through JSON unchanged" do
      for resource <- [Event, EventsByDayMv, EventCount, RawSelect] do
        snapshot = MigrationGenerator.snapshot(resource)

        assert snapshot == snapshot |> Jason.encode!() |> Jason.decode!()
      end
    end
  end

  describe "statements/3" do
    test "a resource with no snapshot creates its table and drops it on rollback" do
      new = %{"events" => snapshot([{"id", "UUID"}, {"name", "String"}])}

      assert {[up], [down]} = MigrationGenerator.statements(new, %{}, MapSet.new())
      assert up == "CREATE TABLE events (id UUID, name String) ENGINE = MergeTree() order by id"
      assert down == "DROP TABLE events"
    end

    test "an added attribute becomes ADD COLUMN" do
      old = %{"events" => snapshot([{"id", "UUID"}])}
      new = %{"events" => snapshot([{"id", "UUID"}, {"amount", "UInt32"}])}

      assert {["ALTER TABLE events ADD COLUMN amount UInt32"],
              ["ALTER TABLE events DROP COLUMN amount"]} =
               MigrationGenerator.statements(new, old, MapSet.new())
    end

    test "a removed attribute becomes DROP COLUMN, restored with its old type" do
      old = %{"events" => snapshot([{"id", "UUID"}, {"amount", "UInt32"}])}
      new = %{"events" => snapshot([{"id", "UUID"}])}

      assert {["ALTER TABLE events DROP COLUMN amount"],
              ["ALTER TABLE events ADD COLUMN amount UInt32"]} =
               MigrationGenerator.statements(new, old, MapSet.new())
    end

    test "a changed type becomes MODIFY COLUMN both ways" do
      old = %{"events" => snapshot([{"amount", "UInt32"}])}
      new = %{"events" => snapshot([{"amount", "UInt64"}])}

      assert {["ALTER TABLE events MODIFY COLUMN amount UInt64"],
              ["ALTER TABLE events MODIFY COLUMN amount UInt32"]} =
               MigrationGenerator.statements(new, old, MapSet.new())
    end

    test "an unchanged resource generates nothing" do
      snapshots = %{"events" => snapshot([{"id", "UUID"}])}

      assert {[], []} = MigrationGenerator.statements(snapshots, snapshots, MapSet.new())
    end

    test "a snapshot with no resource is left alone rather than dropped" do
      old = %{"events" => snapshot([{"id", "UUID"}])}

      assert {[], []} = MigrationGenerator.statements(%{}, old, MapSet.new())
    end

    test "a droppable snapshot with no resource drops the table" do
      old = %{"events" => snapshot([{"id", "UUID"}])}

      assert {["DROP TABLE events"], [create]} =
               MigrationGenerator.statements(%{}, old, MapSet.new(["events"]))

      assert create =~ "CREATE TABLE events"
    end

    test "retyping a column named in the sorting key raises" do
      old = %{"events" => snapshot([{"id", "UUID"}])}
      new = %{"events" => snapshot([{"id", "String"}])}

      assert_raise RuntimeError, ~r/id cannot be retyped/, fn ->
        MigrationGenerator.statements(new, old, MapSet.new())
      end
    end

    test "dropping a column named in the sorting key raises" do
      old = %{"events" => snapshot([{"id", "UUID"}, {"name", "String"}])}
      new = %{"events" => snapshot([{"name", "String"}])}

      assert_raise RuntimeError, ~r/id cannot be dropped/, fn ->
        MigrationGenerator.statements(new, old, MapSet.new())
      end
    end

    test "a table declaring no options can still have a column dropped" do
      old = %{"events" => snapshot([{"a", "String"}, {"b", "String"}], %{"options" => []})}
      new = %{"events" => snapshot([{"a", "String"}], %{"options" => []})}

      assert {["ALTER TABLE events DROP COLUMN b"], _} =
               MigrationGenerator.statements(new, old, MapSet.new())
    end

    test "a column merely sharing a prefix with the sorting key is not refused" do
      old = %{"events" => snapshot([{"id", "UUID"}, {"identity", "String"}])}
      new = %{"events" => snapshot([{"id", "UUID"}, {"identity", "UInt8"}])}

      assert {["ALTER TABLE events MODIFY COLUMN identity UInt8"], _} =
               MigrationGenerator.statements(new, old, MapSet.new())
    end

    test "a changed sorting key raises rather than emitting an ALTER ClickHouse rejects" do
      old = %{"events" => snapshot([{"id", "UUID"}])}
      new = %{"events" => snapshot([{"id", "UUID"}], %{"options" => "order by name"})}

      assert_raise RuntimeError, ~r/cannot ALTER the engine or sorting key/, fn ->
        MigrationGenerator.statements(new, old, MapSet.new())
      end
    end

    test "a changed engine raises for the same reason" do
      old = %{"events" => snapshot([{"id", "UUID"}])}
      new = %{"events" => snapshot([{"id", "UUID"}], %{"engine" => "ReplacingMergeTree()"})}

      assert_raise RuntimeError, ~r/cannot ALTER the engine or sorting key/, fn ->
        MigrationGenerator.statements(new, old, MapSet.new())
      end
    end
  end

  describe "normalize/1" do
    test "a snapshot written before views were supported reads back as a table" do
      assert %{"materialized_view" => nil} =
               MigrationGenerator.normalize(%{"table" => "events", "columns" => []})
    end
  end

  describe "statements/3 with materialized views" do
    test "a view with a destination is created against it and dropped as a view" do
      assert {[up], [down]} =
               MigrationGenerator.statements(%{"events_by_day_mv" => view()}, %{}, MapSet.new())

      assert up == "CREATE MATERIALIZED VIEW events_by_day_mv TO events_by_day AS SELECT 1"
      assert down == "DROP VIEW events_by_day_mv"
    end

    test "a view owning its storage carries the engine and options instead" do
      owning = view(%{"to" => nil})

      assert {[up], _} =
               MigrationGenerator.statements(%{"events_by_day_mv" => owning}, %{}, MapSet.new())

      assert up ==
               "CREATE MATERIALIZED VIEW events_by_day_mv ENGINE = MergeTree() order by id AS SELECT 1"
    end

    test "a changed select redefines the view by dropping and recreating it" do
      old = %{"events_by_day_mv" => view()}
      new = %{"events_by_day_mv" => view(%{"select" => "SELECT 2"})}

      assert {["DROP VIEW events_by_day_mv", create_new],
              ["DROP VIEW events_by_day_mv", create_old]} =
               MigrationGenerator.statements(new, old, MapSet.new())

      assert create_new =~ "AS SELECT 2"
      assert create_old =~ "AS SELECT 1"
    end

    test "attributes changing without the definition leaves the view alone" do
      old = %{"events_by_day_mv" => view()}
      new = %{"events_by_day_mv" => Map.put(view(), "columns", [])}

      assert {[], []} = MigrationGenerator.statements(new, old, MapSet.new())
    end

    test "redefining a view that owns its storage raises rather than discarding it" do
      old = %{"events_by_day_mv" => view(%{"to" => nil})}
      new = %{"events_by_day_mv" => view(%{"to" => nil, "select" => "SELECT 2"})}

      assert_raise RuntimeError, ~r/owns the data it has accumulated/, fn ->
        MigrationGenerator.statements(new, old, MapSet.new())
      end
    end

    test "turning a table into a view raises" do
      old = %{"events" => snapshot([{"id", "UUID"}])}
      new = %{"events" => Map.put(view(), "table", "events")}

      assert_raise RuntimeError, ~r/changed between a table and a materialized view/, fn ->
        MigrationGenerator.statements(new, old, MapSet.new())
      end
    end

    test "a view is created after every table and dropped before every one" do
      new = %{"events_by_day_mv" => view(), "events" => snapshot([{"id", "UUID"}])}

      assert {[create_table, create_view], [drop_view, drop_table]} =
               MigrationGenerator.statements(new, %{}, MapSet.new())

      assert create_table =~ "CREATE TABLE events"
      assert create_view =~ "CREATE MATERIALIZED VIEW"
      assert drop_view == "DROP VIEW events_by_day_mv"
      assert drop_table == "DROP TABLE events"
    end

    test "dropping a view and its destination orders the view first, and reverses" do
      old = %{
        "events_by_day" => snapshot([{"day", "Date"}], %{"table" => "events_by_day"}),
        "events_by_day_mv" => view()
      }

      droppable = MapSet.new(["events_by_day", "events_by_day_mv"])

      assert {["DROP VIEW events_by_day_mv", "DROP TABLE events_by_day"],
              [create_table, create_view]} = MigrationGenerator.statements(%{}, old, droppable)

      assert create_table =~ "CREATE TABLE events_by_day"
      assert create_view =~ "CREATE MATERIALIZED VIEW events_by_day_mv"
    end
  end
end
