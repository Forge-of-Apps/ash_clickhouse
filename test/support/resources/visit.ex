defmodule AshClickhouse.Test.Resource.Visit do
  @moduledoc "A table read through filters that shift a time by an interval."

  use Ash.Resource,
    domain: AshClickhouse.Test.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("visits")
    repo(AshClickhouse.TestRepo)
    engine("MergeTree()")
    options("order by at")
  end

  actions do
    defaults([:read, :create])
    default_accept(:*)

    read :recent do
      filter(expr(at > ago(30, :day)))
    end

    read :since do
      argument(:days, :integer, allow_nil?: false)
      filter(expr(at > ago(^arg(:days), :day)))
    end
  end

  attributes do
    attribute :id, AshClickhouse.Type.ChUUID do
      primary_key?(true)
      allow_nil?(false)
      writable?(false)
      default(&Ash.UUIDv7.generate/0)
    end

    attribute(:page, AshClickhouse.Type.ChString, public?: true, allow_nil?: false)
    attribute(:at, AshClickhouse.Type.ChDateTime, public?: true, allow_nil?: false)
    attribute(:stay_days, AshClickhouse.Type.ChUint16, public?: true, allow_nil?: false)
    attribute(:on, AshClickhouse.Type.ChDate, public?: true, allow_nil?: false)
  end
end
