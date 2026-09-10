defmodule AshClickhouse.Test.Unmigrated.Thing do
  @moduledoc "The only resource in its domain, and not one the generator migrates."

  use Ash.Resource,
    domain: AshClickhouse.Test.Unmigrated.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("things")
    repo(AshClickhouse.TestRepo)
    migrate?(false)
    engine("MergeTree()")
    options("order by id")
  end

  actions do
    defaults([:read])
  end

  attributes do
    attribute :id, AshClickhouse.Type.ChUUID do
      primary_key?(true)
      allow_nil?(false)
      writable?(false)
      default(&Ash.UUIDv7.generate/0)
    end
  end
end
