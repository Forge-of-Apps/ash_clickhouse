defmodule AshClickhouse.Test.Migration.Ignored do
  @moduledoc """
  Resource with `migrate? false`. Its table must never appear in a generated
  migration, and must never be dropped by one either: the generator sees the
  resource claiming the table even though it generates no DDL for it.
  """

  use Ash.Resource,
    domain: AshClickhouse.Test.Migration.Domain,
    data_layer: AshClickhouse.DataLayer

  clickhouse do
    table("ignoreds")
    repo(AshClickhouse.TestRepo)
    migrate?(false)
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
  end
end
