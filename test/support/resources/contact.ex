defmodule AshClickhouse.Test.Resource.Contact do
  @moduledoc "A table whose JSON column holds a union with typed paths at its top."

  use Ash.Resource,
    domain: AshClickhouse.Test.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("contacts")
    repo(AshClickhouse.TestRepo)
    engine("MergeTree()")
    options("order by at")
  end

  actions do
    defaults([:read, :create])
    default_accept(:*)
  end

  attributes do
    attribute :id, AshClickhouse.Type.ChUUID do
      primary_key?(true)
      allow_nil?(false)
      writable?(false)
      default(&Ash.UUIDv7.generate/0)
    end

    attribute(:channel, AshClickhouse.Test.Resource.Types.Channel,
      public?: true,
      allow_nil?: false
    )

    attribute(:at, AshClickhouse.Type.ChDateTime64, public?: true, constraints: [precision: 6])
  end
end
