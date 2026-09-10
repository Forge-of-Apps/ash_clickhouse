defmodule AshClickhouse.MigrationGenerator do
  @moduledoc """
  Generates ClickHouse migrations by diffing resources against snapshots.

  Column types come from each attribute's ClickHouse storage type, so a
  resource is the single source of truth for its table.

  A snapshot is the JSON-encodable shape of one table or materialized view,
  written to `priv/<repo>/snapshots/<table>.json` once a migration for it is
  generated. It records the domain that owned the resource, which is what lets
  a later run tell a resource that was deleted from one that is merely outside
  the run's `--domains` scope. Diffing the current resources against those
  snapshots yields the `up` and `down` statements of the next migration.

  ClickHouse cannot `ALTER` a table's engine or sorting key, nor drop or retype
  a column the sorting key names, so those changes raise rather than emitting a
  migration that would fail halfway through with no transaction to undo it. Key
  columns are recognised by word match against the options string rather than by
  parsing `ORDER BY`, so a column named anywhere in the options counts as one.

  Statements are ordered by direction rather than by kind: views are dropped
  before tables and created after them, so a view is never created before the
  table it reads nor left behind when that table goes, in either direction. A
  view reading another view is not ordered — declare them so that the reader's
  `source` comes first, or split them across two migrations.

  A materialized view is redefined by dropping and recreating it, which is only
  free for one with a `to` table, since that table's data is not the view's to
  lose. Redefining a view that owns its storage would discard everything it has
  accumulated, so that raises too.
  """

  alias AshClickhouse.DataLayer.Info

  @doc "The JSON-encodable shape of the table or view a resource declares."
  def snapshot(resource) do
    %{
      "table" => Info.table(resource),
      "domain" => Atom.to_string(Ash.Resource.Info.domain(resource)),
      "engine" => Info.engine(resource),
      "options" => Info.options(resource),
      "materialized_view" => Info.materialized_view(resource),
      "columns" =>
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.map(&%{"name" => to_string(&1.name), "type" => column_type(&1)})
    }
  end

  @doc """
  Adds the keys a snapshot written before views were supported lacks.

  Snapshots are read back from disk long after they were written, so every one
  loaded goes through here before it is diffed against a fresh one.
  """
  def normalize(snapshot), do: Map.put_new(snapshot, "materialized_view", nil)

  @doc """
  The `CREATE` statement for a snapshot, used by migrations and tests alike.

  A resource is accepted in place of its snapshot, which is what lets a test
  create its tables from the resources through the very statement a migration
  would carry.
  """
  def create_sql(resource) when is_atom(resource) and not is_nil(resource),
    do: resource |> snapshot() |> create_sql()

  def create_sql(%{"materialized_view" => nil} = snapshot) do
    columns = Enum.map_join(snapshot["columns"], ", ", &"#{&1["name"]} #{&1["type"]}")

    String.trim(
      "CREATE TABLE #{snapshot["table"]} (#{columns}) ENGINE = #{snapshot["engine"]} #{snapshot["options"]}"
    )
  end

  def create_sql(%{"materialized_view" => %{"to" => nil} = view} = snapshot) do
    String.trim(
      "CREATE MATERIALIZED VIEW #{snapshot["table"]} ENGINE = #{snapshot["engine"]} #{snapshot["options"]} AS #{view["select"]}"
    )
  end

  def create_sql(%{"materialized_view" => view} = snapshot) do
    "CREATE MATERIALIZED VIEW #{snapshot["table"]} TO #{view["to"]} AS #{view["select"]}"
  end

  @doc """
  The `{up, down}` statements taking the old snapshots to the new ones.

  `droppable` names the tables this run is authoritative over: a snapshot with
  no matching resource is dropped when its table is in that set and left
  untouched otherwise, so narrowing a run with `--domains` cannot destroy the
  tables it did not look at.
  """
  def statements(new, old, droppable) do
    new
    |> Map.keys()
    |> Enum.concat(Map.keys(old))
    |> Enum.uniq()
    |> Enum.map(&{Map.get(new, &1), Map.get(old, &1), &1 in droppable})
    |> Enum.sort_by(&order/1)
    |> Enum.map(fn {new, old, droppable?} -> table_statements(new, old, droppable?) end)
    |> combine()
  end

  defp order({nil, old, _droppable?}), do: if(view?(old), do: 0, else: 1)
  defp order({new, _old, _droppable?}), do: if(view?(new), do: 3, else: 2)

  defp view?(%{"materialized_view" => view}), do: not is_nil(view)
  defp view?(nil), do: false

  defp table_statements(new, nil, _droppable?), do: {[create_sql(new)], [drop_sql(new)]}

  defp table_statements(nil, old, true), do: {[drop_sql(old)], [create_sql(old)]}

  defp table_statements(nil, _old, false), do: {[], []}

  defp table_statements(
         %{"materialized_view" => nil} = new,
         %{"materialized_view" => nil} = old,
         _droppable?
       ) do
    table = new["table"]

    if new["engine"] != old["engine"] or new["options"] != old["options"] do
      raise """
      ClickHouse cannot ALTER the engine or sorting key of #{table}.

      engine:  #{old["engine"]} -> #{new["engine"]}
      options: #{old["options"]} -> #{new["options"]}

      Recreating the table is a data migration, so write it by hand rather than
      generating it.
      """
    end

    new_columns = Map.new(new["columns"], &{&1["name"], &1["type"]})
    old_columns = Map.new(old["columns"], &{&1["name"], &1["type"]})

    new_columns
    |> Map.keys()
    |> Enum.concat(Map.keys(old_columns))
    |> Enum.uniq()
    |> Enum.map(
      &column_statements(
        table,
        new["options"],
        &1,
        Map.get(new_columns, &1),
        Map.get(old_columns, &1)
      )
    )
    |> combine()
  end

  defp table_statements(
         %{"materialized_view" => new_view} = new,
         %{"materialized_view" => old_view} = old,
         _droppable?
       )
       when is_map(new_view) and is_map(old_view) do
    cond do
      definition(new) == definition(old) ->
        {[], []}

      is_nil(new_view["to"]) or is_nil(old_view["to"]) ->
        raise """
        #{new["table"]} owns the data it has accumulated, and redefining a
        materialized view means dropping and recreating it, which would discard
        that data.

        Write the migration by hand, or give the view a `to` table so that its
        data outlives its definition.
        """

      true ->
        {[drop_sql(new), create_sql(new)], [drop_sql(old), create_sql(old)]}
    end
  end

  defp table_statements(%{"table" => table}, _old, _droppable?) do
    raise """
    #{table} changed between a table and a materialized view. The two are
    dropped and created differently and share no data, so switching is a data
    migration — write it by hand.
    """
  end

  defp definition(snapshot), do: Map.take(snapshot, ["engine", "options", "materialized_view"])

  defp drop_sql(%{"materialized_view" => nil} = snapshot), do: "DROP TABLE #{snapshot["table"]}"
  defp drop_sql(snapshot), do: "DROP VIEW #{snapshot["table"]}"

  defp combine(pairs) do
    {Enum.flat_map(pairs, &elem(&1, 0)), pairs |> Enum.reverse() |> Enum.flat_map(&elem(&1, 1))}
  end

  defp column_statements(_table, _options, _column, same, same), do: {[], []}

  defp column_statements(table, _options, column, type, nil) do
    {["ALTER TABLE #{table} ADD COLUMN #{column} #{type}"],
     ["ALTER TABLE #{table} DROP COLUMN #{column}"]}
  end

  defp column_statements(table, options, column, nil, type) do
    refuse_key_column!(table, options, column, "dropped")

    {["ALTER TABLE #{table} DROP COLUMN #{column}"],
     ["ALTER TABLE #{table} ADD COLUMN #{column} #{type}"]}
  end

  defp column_statements(table, options, column, type, was) do
    refuse_key_column!(table, options, column, "retyped")

    {["ALTER TABLE #{table} MODIFY COLUMN #{column} #{type}"],
     ["ALTER TABLE #{table} MODIFY COLUMN #{column} #{was}"]}
  end

  defp refuse_key_column!(table, options, column, change) do
    if Regex.match?(~r/\b#{Regex.escape(column)}\b/, to_string(options)) do
      raise """
      #{table}.#{column} cannot be #{change}: ClickHouse forbids altering a
      column named in the table's sorting key (#{options}).

      Recreating the table is a data migration, so write it by hand rather than
      generating it.
      """
    end
  end

  defp column_type(%{type: type, constraints: constraints}) do
    storage =
      case Ash.Type.storage_type(type, constraints) do
        {:array, {:parameterized, {Ch, ch_type}}} -> {:array, ch_type}
        {:parameterized, {Ch, ch_type}} -> ch_type
      end

    IO.iodata_to_binary(Ch.Types.encode(storage))
  end
end
