# AshClickhouse

A ClickHouse data layer for [Ash](https://hexdocs.pm/ash), built on
[ecto_ch](https://hexdocs.pm/ecto_ch). Forked from
[monoflow-ayvu/ash_clickhouse](https://github.com/monoflow-ayvu/ash_clickhouse)
and extended with a migration generator and materialized views.

The reference documentation lives in the modules themselves — `h AshClickhouse`
in IEx, or `mix docs`. This is the tour.

## Installation

This fork is not on Hex. Depend on it from GitHub:

```elixir
def deps do
  [
    {:ash_clickhouse, github: "Forge-of-Apps/ash_clickhouse"}
  ]
end
```

## A resource

```elixir
defmodule MyApp.ClickhouseRepo do
  use AshClickhouse.Repo, otp_app: :my_app
end

defmodule MyApp.Event do
  use Ash.Resource, domain: MyApp.Analytics, data_layer: AshClickhouse.DataLayer

  clickhouse do
    repo MyApp.ClickhouseRepo
    table "events"
    options "order by (at, id)"
  end

  attributes do
    attribute :id, AshClickhouse.Type.ChUUID,
      primary_key?: true, allow_nil?: false, default: &Ash.UUIDv7.generate/0

    attribute :name, AshClickhouse.Type.ChString
    attribute :amount, AshClickhouse.Type.ChUint32
    attribute :at, AshClickhouse.Type.ChDateTime64, constraints: [precision: 6]
  end
end
```

Add the repo to `:ecto_repos` and configure it as any Ecto repo, and
`mix ash.setup`, `mix ash.codegen` and `mix ash.migrate` cover it alongside
every other data layer.

`AshClickhouse.DataLayer` documents the whole `clickhouse` DSL and what
ClickHouse will not do for you — no transactions, no foreign keys, and no
updates worth declaring. Column types are the `AshClickhouse.Type.Ch*` modules,
whose constraints choose the ClickHouse type rather than only validating the
value; each documents its own.

## A materialized view

A view is a resource whose `clickhouse` block holds a `materialized_view`
section. Its SELECT is written as an `Ecto.Query` and rendered to SQL at
codegen time:

```elixir
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
```

See `AshClickhouse.MaterializedView` for why every column needs
`selected_as/2`, why the query can carry no bound parameters, and when to reach
for raw SQL instead.

## Migrations

`mix ash.codegen` diffs the resources against snapshots under
`priv/<repo>/snapshots` and writes a migration; `mix ash.migrate` applies it.
`mix ash_clickhouse.generate_migrations` and `mix ash_clickhouse.migrate` do
the same for this data layer alone.

ClickHouse has no transactional rollback, so the generator refuses to emit
anything that would fail halfway or destroy data — a changed engine or sorting
key, a dropped or retyped sorting-key column, a redefined view that owns its
storage. `AshClickhouse.MigrationGenerator` documents each refusal;
`mix ash_clickhouse.generate_migrations` documents the `--drop-tables`,
`--dev` and `--check` flags.

## Running the tests

The suite needs a ClickHouse server, taken from `CLICKHOUSE_URL` and defaulting
to `http://default:@localhost:8123/default`:

```sh
CLICKHOUSE_URL=http://user:pass@localhost:8123/ash_clickhouse_test mix test
```
