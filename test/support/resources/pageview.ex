defmodule AshClickhouse.Test.Resource.Pageview do
  @moduledoc "A table sorted by a typed path of its JSON column."

  use Ash.Resource,
    domain: AshClickhouse.Test.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("pageviews")
    repo(AshClickhouse.TestRepo)
    engine("MergeTree()")
    options("order by (site, visitor.user.id, at)")
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

    attribute(:site, AshClickhouse.Type.ChString, public?: true, allow_nil?: false)

    attribute :visitor, AshClickhouse.Type.ChJSON do
      public?(true)
      allow_nil?(false)

      constraints(
        paths: %{
          "user.id" => AshClickhouse.Type.ChString,
          "user.visits" => AshClickhouse.Type.ChUint32
        }
      )
    end

    attribute(:at, AshClickhouse.Type.ChDateTime64, public?: true, constraints: [precision: 6])
  end
end
