defmodule AshClickhouse.MigrationGenerator do
  @moduledoc """
  Generates ClickHouse migrations by diffing resources against snapshots.

  Reached through `mix ash.codegen`, or
  `mix ash_clickhouse.generate_migrations` on its own, which documents the
  flags. Modelled on `AshPostgres.MigrationGenerator`, so a migration is named,
  numbered and developed against in the same way.

  Column types come from each attribute's ClickHouse storage type, so a
  resource is the single source of truth for its table.

  A snapshot is the JSON-encodable shape of one table, written to
  `priv/resource_snapshots/<repo>/<table>/<timestamp>.json` once a migration
  for it is generated. A directory per table rather than a single file means
  two branches can each add a snapshot without colliding, and undoing a
  generation is deleting its migration and its newest snapshot. It records the
  domain that owned the resource, which is what lets a later run tell a
  resource that was deleted from one that is merely outside the run's
  `--domains` scope.

  ClickHouse cannot `ALTER` a table's engine or sorting key, nor drop or retype
  a column the sorting key names, so those changes raise rather than emitting a
  migration that would fail halfway through with no transaction to undo it. Key
  columns are recognised by word match against the options string rather than by
  parsing `ORDER BY`, so a column named anywhere in the options counts as one.
  """

  alias AshClickhouse.DataLayer.Info

  defstruct snapshot_path: nil,
            migration_path: nil,
            name: nil,
            quiet: false,
            dry_run: false,
            check: false,
            dev: false,
            snapshots_only: false,
            auto_name: false,
            drop_tables: false,
            format: true

  @doc """
  Writes the migrations and snapshots taking the given domains' resources from
  their last snapshot to now.

  Options are the ones `mix ash_clickhouse.generate_migrations` documents.
  Nothing is written for `:check` or `:dry_run`: the first raises
  `Ash.Error.Framework.PendingCodegen` carrying what it would have written, the
  second prints it.
  """
  def generate(domains, opts \\ []) do
    opts = struct(__MODULE__, opts)

    clickhouse =
      domains
      |> List.wrap()
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.filter(&(Ash.Resource.Info.data_layer(&1) == AshClickhouse.DataLayer))

    files =
      clickhouse
      |> Enum.group_by(&Info.repo/1)
      |> Enum.sort_by(fn {repo, _resources} -> inspect(repo) end)
      |> Enum.flat_map(fn {repo, resources} ->
        files_for_repo(repo, Enum.filter(resources, &Info.migrate?/1), domains, clickhouse, opts)
      end)

    case files do
      [] ->
        unless opts.quiet do
          Mix.shell().info(
            "No changes detected, so no migrations or snapshots have been created."
          )
        end

        :ok

      files ->
        cond do
          opts.check ->
            raise Ash.Error.Framework.PendingCodegen, diff: files

          opts.dry_run ->
            Mix.shell().info(
              Enum.map_join(files, "\n\n", fn {file, contents} -> "#{file}\n#{contents}" end)
            )

          true ->
            Enum.each(files, fn {file, contents} ->
              Mix.Generator.create_file(file, contents,
                force: true,
                quiet: opts.quiet,
                format_elixir: opts.format and Path.extname(file) == ".exs"
              )
            end)
        end
    end
  end

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

  defp files_for_repo(repo, resources, domains, clickhouse, opts) do
    migration_path = migration_path(opts, repo)
    snapshot_path = snapshot_path(opts, repo)

    resolve_dev_migrations!(migration_path, snapshot_path, repo, opts)

    new = Map.new(resources, &{Info.table(&1), snapshot(&1)})
    old = read_snapshots(snapshot_path)

    orphans = orphans(old, domains, clickhouse)
    droppable = if opts.drop_tables, do: orphans, else: MapSet.new()

    report_orphans(orphans, opts)

    snapshot_files =
      if Map.take(old, Map.keys(new)) == new do
        []
      else
        Enum.map(new, fn {table, snapshot} ->
          {Path.join([snapshot_path, table, "#{timestamp()}#{dev_suffix(opts)}.json"]),
           Jason.encode!(snapshot, pretty: true)}
        end)
      end

    case statements(new, old, droppable) do
      {[], []} ->
        snapshot_files

      {up, down} ->
        remove_orphan_snapshots(snapshot_path, droppable, opts)

        if opts.snapshots_only do
          snapshot_files
        else
          [migration_file(repo, migration_path, up, down, opts) | snapshot_files]
        end
    end
  end

  defp migration_file(repo, migration_path, up, down, opts) do
    require_name!(opts)

    name = opts.name || "migrate_resources#{next_count(migration_path)}"
    file = Path.join(migration_path, "#{timestamp()}_#{name}#{dev_suffix(opts)}.exs")
    module = Module.concat([repo, Migrations, Macro.camelize(name)])

    contents = """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      Updates resources based on their most recent snapshots.

      This file was autogenerated with `mix ash_clickhouse.generate_migrations`
      \"\"\"

      use Ecto.Migration

      def up do
    #{Enum.map_join(up, "\n", &"    execute(#{inspect(&1)})")}
      end

      def down do
    #{Enum.map_join(down, "\n", &"    execute(#{inspect(&1)})")}
      end
    end
    """

    {file, contents}
  end

  defp require_name!(opts) do
    if !opts.name && !opts.dry_run && !opts.check && !opts.snapshots_only && !opts.dev &&
         !opts.auto_name do
      raise """
      Name must be provided when generating migrations, unless `--dry-run` or `--check` or `--dev` is also provided.

      Please provide a name. for example:

          mix ash_clickhouse.generate_migrations <name> ...args
      """
    end

    :ok
  end

  defp next_count(migration_path) do
    migration_path
    |> Path.join("*_migrate_resources*")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      path
      |> Path.basename()
      |> String.split("_migrate_resources", parts: 2)
      |> Enum.at(1)
      |> Integer.parse()
      |> case do
        {integer, _} -> integer
        _ -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp dev_suffix(%{dev: true}), do: "_dev"
  defp dev_suffix(_opts), do: ""

  defp read_snapshots(snapshot_path) do
    snapshot_path
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(fn dir ->
      dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.max(fn -> nil end)
      |> case do
        nil -> []
        file -> [{Path.basename(dir), file |> File.read!() |> Jason.decode!()}]
      end
    end)
    |> Map.new()
  end

  defp remove_orphan_snapshots(snapshot_path, droppable, opts) do
    unless opts.dry_run or opts.check do
      Enum.each(droppable, &File.rm_rf!(Path.join(snapshot_path, &1)))
    end
  end

  defp orphans(old, domains, clickhouse) do
    owned = MapSet.new(List.wrap(domains), &Atom.to_string/1)
    claimed = MapSet.new(clickhouse, &Info.table/1)

    for {table, snapshot} <- old,
        snapshot["domain"] in owned,
        table not in claimed,
        into: MapSet.new(),
        do: table
  end

  defp report_orphans(orphans, opts) do
    if not opts.drop_tables and not opts.quiet and not Enum.empty?(orphans) do
      Mix.shell().info("""
      No resource claims these tables any more:

      #{Enum.map_join(orphans, "\n", &"  * #{&1}")}

      Renaming a resource's `table` looks exactly like deleting it, so nothing
      is dropped without --drop-tables. Pass it once the data really is
      disposable, or hand-write the rename.
      """)
    end
  end

  defp resolve_dev_migrations!(migration_path, snapshot_path, repo, opts) do
    dev_migrations = dev_migrations(migration_path)

    cond do
      dev_migrations == [] or opts.dev ->
        :ok

      opts.check ->
        Mix.raise("""
        Codegen check failed.

        You have migrations remaining that were generated with the --dev flag:

        #{Enum.map_join(dev_migrations, "\n", &"  * #{Path.basename(&1)}")}

        Run `mix ash.codegen <name>` to replace them with a named migration.
        """)

      opts.dry_run ->
        :ok

      true ->
        roll_back_dev_migrations(dev_migrations, repo)
        remove_dev_snapshots(snapshot_path)
    end
  end

  defp dev_migrations(migration_path) do
    migration_path
    |> Path.join("*_dev.exs")
    |> Path.wildcard()
  end

  defp remove_dev_snapshots(snapshot_path) do
    snapshot_path
    |> Path.join("*/*_dev.json")
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)
  end

  defp roll_back_dev_migrations(dev_migrations, repo) do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        {repo, query, query_opts} =
          Ecto.Migration.SchemaMigration.versions(repo, repo.config(), nil)

        applied = repo.all(query, query_opts)

        dev_migrations
        |> Enum.map(&migration_module!/1)
        |> Enum.sort()
        |> Enum.reverse()
        |> Enum.filter(fn {version, _module} -> version in applied end)
        |> Enum.each(fn {version, module} ->
          Ecto.Migration.Runner.run(repo, [], version, module, :forward, :down, :down, all: true)
          Ecto.Migration.SchemaMigration.down(repo, repo.config(), version, [])
        end)
      end)

    Enum.each(dev_migrations, &File.rm!/1)
  end

  defp migration_module!(file) do
    {version, "_" <> _name} = file |> Path.basename() |> Path.rootname() |> Integer.parse()

    module =
      file
      |> Code.compile_file()
      |> Enum.map(&elem(&1, 0))
      |> Enum.find(&function_exported?(&1, :__migration__, 0))

    unless module do
      raise Ecto.MigrationError, "file #{Path.relative_to_cwd(file)} does not define a migration"
    end

    {version, module}
  end

  defp migration_path(%{migration_path: path}, _repo) when not is_nil(path), do: path

  defp migration_path(_opts, repo),
    do: Path.join(AshClickhouse.Mix.Helpers.source_repo_priv(repo), "migrations")

  defp snapshot_path(%{snapshot_path: path}, _repo) when not is_nil(path), do: path

  defp snapshot_path(_opts, repo) do
    config = repo.config()
    app = Keyword.fetch!(config, :otp_app)

    Path.join([
      Mix.Project.deps_paths()[app] || File.cwd!(),
      "priv/resource_snapshots",
      repo |> Module.split() |> List.last() |> Macro.underscore()
    ])
  end

  defp timestamp, do: Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")

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
