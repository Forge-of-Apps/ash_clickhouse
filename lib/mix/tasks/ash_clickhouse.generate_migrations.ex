defmodule Mix.Tasks.AshClickhouse.GenerateMigrations do
  @moduledoc """
  Generates ClickHouse migrations from the resources' current state.

  Run by `mix ash.codegen`, which calls `AshClickhouse.DataLayer.codegen/1`, so
  ClickHouse migrations are generated in the same run as every other
  extension's. Run it directly to generate only these.

  A migration's version is a second-resolution timestamp, bumped until no file
  in the directory already claims it, and doubles as the suffix of the module
  name, so neither the filename, the Ecto version nor the module can collide
  with a migration that is already there.

  Every run that writes a migration writes the snapshots too, so each migration
  carries only the change since the run before it and applying them in order is
  always correct. Migrations are never deleted or rewritten: one that exists
  may already have been applied, and ClickHouse has no transactional rollback
  to undo it with.

  ## Flags

    * `--name` names the migration. Defaults to `migrate_resources`.
    * `--drop-tables` lets the run emit `DROP TABLE` for a snapshot no
      resource claims any more. Without it such a table is only reported,
      because a renamed `table` looks exactly like a deleted resource and a
      dropped table takes its data with it.
    * `--check` writes nothing and raises if a migration is outstanding, or if
      a migration generated with `--dev` is still carrying its placeholder name
    * `--dry-run` prints the migration it would write
    * `--dev` only prefixes the name with `dev_`, marking a migration whose
      name has not been chosen yet. Rename it by hand once it has one.
    * `--domains` limits the run to the given domains. A snapshot owned by a
      domain outside the run is never dropped.
    * `--migrations-path` and `--snapshot-path` write elsewhere than the repo's
      own directories. Snapshots are repo state rather than migration-directory
      state, so the two are independent: pointing migrations at the nested
      `migrations/tenants` directory leaves the snapshots where they were.

  Resources opt in through `migrate?` in their `clickhouse` section. A repo is
  still visited when every one of its resources has opted out, because the
  snapshots it left behind are still its own to report on.
  """

  @shortdoc "Generates ClickHouse migrations from the resources' current state."

  use Mix.Task

  alias AshClickhouse.DataLayer.Info
  alias AshClickhouse.MigrationGenerator

  @switches [
    check: :boolean,
    dry_run: :boolean,
    dev: :boolean,
    name: :string,
    domains: :string,
    migrations_path: :string,
    snapshot_path: :string,
    drop_tables: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {parsed, _, _} = argv |> Enum.reject(&is_nil/1) |> OptionParser.parse(switches: @switches)

    opts = Keyword.merge([check: false, dry_run: false, dev: false, drop_tables: false], parsed)

    domains =
      opts
      |> Keyword.take([:domains])
      |> Enum.flat_map(fn {key, value} -> ["--#{key}", value] end)
      |> Ash.Mix.Tasks.Helpers.domains!()

    clickhouse =
      domains
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.filter(&(Ash.Resource.Info.data_layer(&1) == AshClickhouse.DataLayer))

    clickhouse
    |> Enum.group_by(&Info.repo/1)
    |> Enum.each(fn {repo, resources} ->
      generate({repo, Enum.filter(resources, &Info.migrate?/1)}, opts, domains, clickhouse)
    end)
  end

  defp generate({repo, resources}, opts, domains, clickhouse) do
    migrations_path =
      AshClickhouse.Mix.Helpers.migrations_path(Keyword.take(opts, [:migrations_path]), repo)

    snapshots_path =
      opts[:snapshot_path] ||
        Path.join(AshClickhouse.Mix.Helpers.source_repo_priv(repo), "snapshots")

    if opts[:check] and not opts[:dev] and dev_migrations(migrations_path) != [] do
      Mix.raise("""
      Codegen check failed.

      Migrations generated with --dev are still carrying their placeholder
      name:

      #{Enum.map_join(dev_migrations(migrations_path), "\n", &"  * #{&1}")}

      Rename each to the name you settled on, and rename its module to match.
      """)
    end

    new = Map.new(resources, &{Info.table(&1), MigrationGenerator.snapshot(&1)})

    old =
      snapshots_path
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Map.new(
        &{Path.basename(&1, ".json"),
         &1 |> File.read!() |> Jason.decode!() |> MigrationGenerator.normalize()}
      )

    orphans = orphans(old, domains, clickhouse)
    droppable = if opts[:drop_tables], do: orphans, else: MapSet.new()

    report_orphans(orphans, opts)

    case MigrationGenerator.statements(new, old, droppable) do
      {[], []} ->
        refresh_snapshots(snapshots_path, new, old, opts)

      {up, down} ->
        name = "#{if opts[:dev], do: "dev_"}#{opts[:name] || "migrate_resources"}"

        version =
          DateTime.utc_now()
          |> Calendar.strftime("%Y%m%d%H%M%S")
          |> String.to_integer()
          |> free_version(migrations_path)

        file = Path.join(migrations_path, "#{version}_#{name}.exs")
        contents = migration_source(repo, name, version, up, down)

        cond do
          opts[:check] ->
            raise Ash.Error.Framework.PendingCodegen, diff: %{file => contents}

          opts[:dry_run] ->
            Mix.shell().info("Would write #{file}:\n\n#{contents}")

          true ->
            File.mkdir_p!(migrations_path)
            File.write!(file, contents)
            Mix.shell().info("Generated #{file}")
            write_snapshots(snapshots_path, new, droppable)
        end
    end
  end

  defp dev_migrations(migrations_path) do
    migrations_path
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.filter(&Regex.match?(~r/^\d{14}_dev_/, &1))
  end

  defp report_orphans(orphans, opts) do
    if not opts[:drop_tables] and not Enum.empty?(orphans) do
      Mix.shell().info("""
      No resource claims these tables any more:

      #{Enum.map_join(orphans, "\n", &"  * #{&1}")}

      Renaming a resource's `table` looks exactly like deleting it, so nothing
      is dropped without --drop-tables. Pass it once the data really is
      disposable, or hand-write the rename.
      """)
    end
  end

  defp refresh_snapshots(snapshots_path, new, old, opts) do
    if not opts[:check] and not opts[:dry_run] and Map.take(old, Map.keys(new)) != new do
      write_snapshots(snapshots_path, new, MapSet.new())
    end

    :ok
  end

  defp orphans(old, domains, clickhouse) do
    owned = MapSet.new(domains, &Atom.to_string/1)
    claimed = MapSet.new(clickhouse, &Info.table/1)

    for {table, snapshot} <- old,
        snapshot["domain"] in owned,
        table not in claimed,
        into: MapSet.new(),
        do: table
  end

  defp free_version(version, migrations_path) do
    if Path.wildcard(Path.join(migrations_path, "#{version}_*.exs")) == [] do
      version
    else
      free_version(version + 1, migrations_path)
    end
  end

  defp write_snapshots(snapshots_path, snapshots, droppable) do
    File.mkdir_p!(snapshots_path)

    for table <- droppable do
      File.rm!(Path.join(snapshots_path, "#{table}.json"))
      Mix.shell().info("Removed snapshot for dropped table #{table}")
    end

    for {table, snapshot} <- snapshots do
      File.write!(
        Path.join(snapshots_path, "#{table}.json"),
        Jason.encode!(snapshot, pretty: true)
      )
    end
  end

  defp migration_source(repo, name, version, up, down) do
    """
    defmodule #{inspect(repo)}.Migrations.#{Macro.camelize(name)}#{version} do
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
  end
end
