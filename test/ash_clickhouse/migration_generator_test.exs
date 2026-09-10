defmodule AshClickhouse.MigrationGeneratorTest do
  use ExUnit.Case, async: true

  alias AshClickhouse.MigrationGenerator
  alias AshClickhouse.Test.Migration.Event

  defp snapshot(columns, overrides \\ %{}) do
    Map.merge(
      %{
        "table" => "events",
        "engine" => "MergeTree()",
        "options" => "order by id",
        "columns" => Enum.map(columns, fn {name, type} -> %{"name" => name, "type" => type} end)
      },
      overrides
    )
  end

  describe "snapshot/1" do
    test "reads the table, engine, options and column types off the resource" do
      assert %{
               "table" => "events",
               "engine" => "MergeTree()",
               "options" => "order by id",
               "columns" => [
                 %{"name" => "id", "type" => "UUID"},
                 %{"name" => "name", "type" => "String"},
                 %{"name" => "amount", "type" => "UInt32"},
                 %{"name" => "at", "type" => "DateTime64(6)"}
               ]
             } = MigrationGenerator.snapshot(Event)
    end

    test "round-trips through JSON unchanged" do
      snapshot = MigrationGenerator.snapshot(Event)

      assert snapshot == snapshot |> Jason.encode!() |> Jason.decode!()
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
end
