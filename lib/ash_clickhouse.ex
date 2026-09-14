defmodule AshClickhouse do
  @moduledoc """
  A ClickHouse data layer for [Ash](https://hexdocs.pm/ash), built on
  [ecto_ch](https://hexdocs.pm/ecto_ch).

  Start at `AshClickhouse.DataLayer`, which documents the `clickhouse` DSL a
  resource uses to say where and how it is stored, and what ClickHouse will
  not do for you — no transactions, no foreign keys, and no updates worth
  declaring.

  ## The pieces

    * `AshClickhouse.DataLayer` — the data layer and its DSL.
    * `AshClickhouse.Repo` — what a repo module uses, and the callbacks it may
      override.
    * `AshClickhouse.MaterializedView` — declaring a resource as a view over
      another table, with its SELECT written as an `Ecto.Query`.
    * `AshClickhouse.MigrationGenerator` — how resources are diffed into
      migrations, and which changes it refuses to generate.
    * `AshClickhouse.Type.ChString` and its siblings under `AshClickhouse.Type`
      — the column types. Their constraints choose the ClickHouse type rather
      than only validating the value.

  ## Mix tasks

    * `mix ash_clickhouse.generate_migrations` — diff resources into a
      migration. Usually reached through `mix ash.codegen`, which runs it
      alongside every other extension's codegen.
    * `mix ash_clickhouse.migrate` and `mix ash_clickhouse.rollback` — apply
      and undo them. `mix ash.migrate` runs the first for you.
    * `mix ash_clickhouse.create` and `mix ash_clickhouse.drop` — create and
      drop the databases themselves, as `mix ash.setup` and `mix ash.tear_down`
      do.

  ## Short type names

  An attribute names its type by module — `attribute :name,
  AshClickhouse.Type.ChString` — which always works and is what this library's
  documentation uses.

  Ash also allows short names, but only for types an app has registered:

      config :ash, :custom_types,
        ch_string: AshClickhouse.Type.ChString,
        ch_uuid: AshClickhouse.Type.ChUUID

  Register the ones you want; the full set is listed in this library's own
  `config/config.exs`. Until then a short name resolves to nothing — and note
  that `:uuid` resolves to `Ash.Type.UUID`, not `AshClickhouse.Type.ChUUID`,
  which has no ClickHouse storage type and so cannot be stored or migrated.
  """

  @doc """
  Hello world.

  ## Examples

      iex> AshClickhouse.hello()
      :world

  """
  def hello do
    :world
  end
end
