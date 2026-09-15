# AshClickhouse

A ClickHouse data layer for [Ash](https://ash-hq.org), forked from
[monoflow-ayvu/ash_clickhouse](https://github.com/monoflow-ayvu/ash_clickhouse)
and extended with a migration generator.

## Installation

This fork is not on Hex. Depend on it from GitHub:

```elixir
def deps do
  [
    {:ash_clickhouse, github: "Forge-of-Apps/ash_clickhouse"}
  ]
end
```

## Declaring a table

```elixir
defmodule MyApp.Event do
  use Ash.Resource, domain: MyApp.Analytics, data_layer: AshClickhouse.DataLayer

  clickhouse do
    repo MyApp.ClickhouseRepo
    table "events"
    engine "MergeTree()"
    options "order by id"
  end

  attributes do
    attribute :id, AshClickhouse.Type.ChUUID, primary_key?: true, allow_nil?: false
    attribute :name, AshClickhouse.Type.ChString, allow_nil?: false
    attribute :amount, AshClickhouse.Type.ChUint32
  end
end
```

Column types come from the `AshClickhouse.Type.Ch*` modules, whose constraints
choose the ClickHouse type: `nullable?`, `low_cardinality?`, `precision` and so
on. An attribute whose type has no ClickHouse storage type — `Ash.Type.UUID`,
say, which `uuid_primary_key` gives you — cannot be migrated; use `ChUUID`.

## Migrations

`mix ash.codegen add_events` generates ClickHouse migrations alongside every
other extension's, by diffing the resources against the snapshots under
`priv/resource_snapshots/<repo>/<table>/`.
`mix ash_clickhouse.generate_migrations` runs the same thing on its own, and
`mix ash.migrate` applies the result.

The first argument names the migration, as it does in
`mix ash_postgres.generate_migrations`, and a name is required unless
`--dry-run`, `--check`, `--dev` or `--auto-name` excuses it.

`--dev` is for a change you are still working on. It writes
`<timestamp>_<name>_dev.exs` and a matching `_dev` snapshot; the next named run
rolls those migrations back, deletes them and their snapshots, and writes one
migration in their place, so iterating leaves no trail of half-steps behind.
`--check` fails while any are still there.

Migrations are otherwise never rewritten or deleted: one that exists may
already have been applied, and ClickHouse has no transactional rollback to undo
it with.

A snapshot no resource claims any more is reported but not dropped. Renaming a
resource's `table` looks exactly like deleting it, so `DROP TABLE` is opt-in
through `--drop-tables`; run codegen with it once the data really is
disposable, and hand-write the rename otherwise.

These changes raise rather than emitting DDL that ClickHouse would reject or
that would silently destroy data:

- changing a table's engine or sorting key
- dropping or retyping a column the sorting key names

Each is a data migration. Write it by hand.

`mix ash_clickhouse.generate_migrations` documents the rest of the flags.

## schema_migrations

Starting an `AshClickhouse.Repo` settles `ecto_ch`'s `default_table_engine` on
`MergeTree` unless the application has already chosen one. `ecto_ch` would
otherwise default to `TinyLog`, which supports no `DELETE`: `Ecto.Migrator`
runs a migration's `down` and then cannot remove its version row, leaving the
schema changed but still recorded as applied. Every generated table names its
own engine, so the default only ever reaches `schema_migrations`.

## Running the tests

The suite needs a ClickHouse server, taken from `CLICKHOUSE_URL` and defaulting
to `http://default:@localhost:8123/default`:

```sh
CLICKHOUSE_URL=http://user:pass@localhost:8123/ash_clickhouse_test mix test
```
