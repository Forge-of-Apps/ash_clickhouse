defmodule AshClickhouse.MigrationGenerator do
  @moduledoc """
  Generates ClickHouse migrations by diffing resources against snapshots.

  Column types come from each attribute's ClickHouse storage type, so a
  resource is the single source of truth for its table.

  A snapshot is the JSON-encodable shape of one table, written to
  `priv/<repo>/snapshots/<table>.json` once a migration for it is generated. It
  records the domain that owned the resource, which is what lets a later run
  tell a resource that was deleted from one that is merely outside the run's
  `--domains` scope. Diffing the current resources against those snapshots
  yields the `up` and `down` statements of the next migration.

  ClickHouse cannot `ALTER` a table's engine or sorting key, nor drop or retype
  a column the sorting key names, so those changes raise rather than emitting a
  migration that would fail halfway through with no transaction to undo it. Key
  columns are recognised by word match against the options string rather than by
  parsing `ORDER BY`, so a column named anywhere in the options counts as one.
  """

  alias AshClickhouse.DataLayer.Info

  @doc "The JSON-encodable shape of the table a resource declares."
  def snapshot(resource) do
    %{
      "table" => Info.table(resource),
      "domain" => Atom.to_string(Ash.Resource.Info.domain(resource)),
      "engine" => Info.engine(resource),
      "options" => Info.options(resource),
      "columns" =>
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.map(&%{"name" => to_string(&1.name), "type" => column_type(&1)})
    }
  end

  @doc """
  The `CREATE TABLE` statement for a snapshot, used by migrations and tests
  alike.

  A resource is accepted in place of its snapshot, which is what lets a test
  create its tables from the resources through the very statement a migration
  would carry.
  """
  def create_sql(resource) when is_atom(resource) and not is_nil(resource),
    do: resource |> snapshot() |> create_sql()

  def create_sql(snapshot) do
    columns = Enum.map_join(snapshot["columns"], ", ", &"#{&1["name"]} #{&1["type"]}")

    String.trim(
      "CREATE TABLE #{snapshot["table"]} (#{columns}) ENGINE = #{snapshot["engine"]} #{snapshot["options"]}"
    )
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
    |> Enum.map(&table_statements(Map.get(new, &1), Map.get(old, &1), &1 in droppable))
    |> combine()
  end

  defp table_statements(new, nil, _droppable?), do: {[create_sql(new)], [drop_sql(new)]}

  defp table_statements(nil, old, true), do: {[drop_sql(old)], [create_sql(old)]}

  defp table_statements(nil, _old, false), do: {[], []}

  defp table_statements(new, old, _droppable?) do
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

  defp drop_sql(snapshot), do: "DROP TABLE #{snapshot["table"]}"

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
