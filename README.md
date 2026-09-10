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

`mix ash.codegen` generates ClickHouse migrations alongside every other
extension's, by diffing the resources against the snapshots under
`priv/<repo>/snapshots`. `mix ash_clickhouse.generate_migrations` runs the same
thing on its own, and `mix ash_clickhouse.migrate` applies the result.

A snapshot no resource claims any more is reported but not dropped. Renaming a
resource's `table` looks exactly like deleting it, so `DROP TABLE` is opt-in
through `--drop-tables`; run codegen with it once the data really is
disposable, and hand-write the rename otherwise.

`--check` fails while a migration generated with `--dev` still carries its
placeholder name, so one cannot reach a release unnoticed.

Generated migrations are never rewritten or deleted: one that exists may
already have been applied, and ClickHouse has no transactional rollback to undo
it with. `--dev` only prefixes the name, marking a migration whose name has not
been chosen yet.

These changes raise rather than emitting DDL that ClickHouse would reject or
that would silently destroy data:

- changing a table's engine or sorting key
- dropping or retyping a column the sorting key names

Each is a data migration. Write it by hand.

## Running the tests

The suite needs a ClickHouse server, taken from `CLICKHOUSE_URL` and defaulting
to `http://default:@localhost:8123/default`:

```sh
CLICKHOUSE_URL=http://user:pass@localhost:8123/ash_clickhouse_test mix test
```
