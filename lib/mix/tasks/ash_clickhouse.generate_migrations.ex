defmodule Mix.Tasks.AshClickhouse.GenerateMigrations do
  @moduledoc """
  Generates migrations, and stores a snapshot of your resources.

  Run by `mix ash.codegen`, which calls `AshClickhouse.DataLayer.codegen/1`, so
  ClickHouse migrations are generated in the same run as every other
  extension's. Run it directly to generate only these.
  `AshClickhouse.MigrationGenerator` does the diffing and documents the changes
  it refuses to generate.

  ## Examples

      mix ash_clickhouse.generate_migrations add_events
      mix ash_clickhouse.generate_migrations --dev
      mix ash_clickhouse.generate_migrations --check

  ## Naming

  The first argument names the migration, as with
  `mix ash_postgres.generate_migrations`. A name is required unless
  `--dry-run`, `--check`, `--dev` or `--auto-name` is given; `--auto-name`
  falls back to `migrate_resources<n>`, counting up from the migrations already
  there.

  ## Development migrations

  `--dev` writes `<timestamp>_<name>_dev.exs` and a matching `_dev` snapshot,
  for a change you are still working on and have not named yet. The next named
  run rolls those migrations back, deletes them and their snapshots, and
  generates one migration in their place, so iterating leaves no trail of
  half-steps behind. `--check` fails while any are still there.

  ## Snapshots

  Snapshots live in a directory per table, under
  `priv/resource_snapshots/<repo>/<table>/`, each named for the moment it was
  taken. Two branches can each add one without colliding, and undoing a
  generation is deleting its migration and its newest snapshot rather than
  redoing the lot.

  Migrations are otherwise never rewritten or deleted: one that exists may
  already have been applied, and ClickHouse has no transactional rollback to
  undo it with.

  ## Command line options

    * `--domains` - the domains whose resources should be migrated
    * `--name` - the migration's name, as an option rather than the first
      argument
    * `--auto-name` - name the migration `migrate_resources<n>` rather than
      requiring a name
    * `--dev` - write a development migration, to be replaced by the next named
      run
    * `--check` - write nothing, and fail if a migration is outstanding or a
      `--dev` migration is still there
    * `--dry-run` - print what would be written
    * `--snapshots-only` - write the snapshots without a migration
    * `--drop-tables` - emit `DROP TABLE` for a snapshot no resource claims any
      more. Without it such a table is only reported, because a renamed `table`
      looks exactly like a deleted resource and a dropped table takes its data
      with it
    * `--quiet` - do not log what is written
    * `--no-format` - do not format the generated migration
    * `--migration-path` and `--snapshot-path` - write elsewhere than the
      repo's own directories

  Resources opt in through `migrate?` in their `clickhouse` section. A repo is
  still visited when every one of its resources has opted out, because the
  snapshots it left behind are still its own to report on.
  """

  @shortdoc "Generates migrations, and stores a snapshot of your resources"

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {name, argv} =
      case argv do
        ["-" <> _ | _] -> {nil, argv}
        [first | rest] -> {first, rest}
        [] -> {nil, []}
      end

    {opts, _} =
      OptionParser.parse!(argv,
        strict: [
          domains: :string,
          snapshot_path: :string,
          migration_path: :string,
          quiet: :boolean,
          snapshots_only: :boolean,
          auto_name: :boolean,
          name: :string,
          no_format: :boolean,
          dry_run: :boolean,
          check: :boolean,
          dev: :boolean,
          drop_tables: :boolean
        ]
      )

    domains = AshClickhouse.Mix.Helpers.domains!(opts, argv)

    opts =
      opts
      |> Keyword.put(:format, !opts[:no_format])
      |> Keyword.delete(:no_format)
      |> Keyword.put_new(:name, name)

    AshClickhouse.MigrationGenerator.generate(domains, opts)
  end
end
