defmodule AshClickhouse.Test.Migration.Event do
  @moduledoc "Plain table the migration generator tests diff."

  use Ash.Resource,
    domain: AshClickhouse.Test.Migration.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("events")
    repo(AshClickhouse.TestRepo)
    engine("MergeTree()")
    options("order by id")
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

    attribute(:name, AshClickhouse.Type.ChString, public?: true, allow_nil?: false)
    attribute(:amount, AshClickhouse.Type.ChUint32, public?: true)
    attribute(:at, AshClickhouse.Type.ChDateTime64, public?: true, constraints: [precision: 6])
  end
end
