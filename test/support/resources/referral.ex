defmodule AshClickhouse.Test.Resource.Referral do
  @moduledoc "A table whose JSON column holds a union, its members' fields typed under `value`."

  use Ash.Resource,
    domain: AshClickhouse.Test.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("referrals")
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

    attribute(:origin, AshClickhouse.Test.Resource.Types.Origin, public?: true, allow_nil?: false)
    attribute(:at, AshClickhouse.Type.ChDateTime64, public?: true, constraints: [precision: 6])
  end
end
