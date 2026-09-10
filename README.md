# AshClickhouse

A ClickHouse data layer for [Ash](https://ash-hq.org), forked from
[monoflow-ayvu/ash_clickhouse](https://github.com/monoflow-ayvu/ash_clickhouse)
and extended with a migration generator and materialized views.

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

## Declaring a materialized view

A materialized view is an insert trigger on `source`: every block inserted
there is run through the view's SELECT and the result written on. With `to` it
is written into a table some other resource owns; without `to` the view owns
its own storage, built from the section's `engine` and `options`.

```elixir
defmodule MyApp.EventsByDayMv do
  use Ash.Resource, domain: MyApp.Analytics, data_layer: AshClickhouse.DataLayer

  import Ecto.Query

  clickhouse do
    repo MyApp.ClickhouseRepo
    table "events_by_day_mv"

    materialized_view do
      source MyApp.Event
      to MyApp.EventsByDay

      query fn events ->
        from e in events,
          group_by: selected_as(:day),
          select: %{
            day: selected_as(fragment("toDate(?)", e.at), :day),
            events: selected_as(count(), :events)
          }
      end
    end
  end

  attributes do
    attribute :day, AshClickhouse.Type.ChDate
    attribute :events, AshClickhouse.Type.ChUint64
  end
end
```

`source` and `to` take a resource or a bare table name. `query` receives the
source table and returns the `Ecto.Query` the view runs, rendered to SQL
through `ecto_ch` at codegen time — no repo has to be running, because a view's
SELECT is DDL rather than a query anyone executes. Reach for `fragment/1` where
Ecto has no syntax for a ClickHouse function, and for `select` with raw SQL
where it has none for the statement.

A view's SELECT is stored once, so it can carry no bound parameters: a pinned
`^value` is refused, while a literal is written into the SQL.

**Name every selected column with `selected_as/2`.** ClickHouse matches a
view's output to its destination table by column name, filling anything
unmatched with that column's default rather than failing, and an unaliased
column arrives as `toDate(at)` and matches nothing. A name the destination does
not have is refused for the same reason — it would be computed on every insert
and then dropped. A destination column the SELECT skips is left to its default,
which is a legitimate thing to want.

Prefer `to`. Redefining a view means dropping and recreating it, which costs
nothing when the data lives in a table the view does not own, and costs
everything the view has accumulated when it does — so the generator refuses
the latter.

The view's columns come from its SELECT, so the resource's attributes are not
used to build the DDL. They describe what the SELECT returns and have to match
it.

## Migrations

`mix ash.codegen` generates ClickHouse migrations alongside every other
extension's, by diffing the resources against the snapshots under
`priv/<repo>/snapshots`. `mix ash_clickhouse.generate_migrations` runs the same
thing on its own, and `mix ash_clickhouse.migrate` applies the result.

Statements are ordered by direction: views are dropped before tables and
created after them, so neither direction leaves a view pointing at a table that
is not there. A view reading another view is not ordered — declare the reader's
`source` first, or split the two across migrations.

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
- redefining a materialized view that owns its storage
- turning a table into a view, or a view into a table

Each is a data migration. Write it by hand.

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
