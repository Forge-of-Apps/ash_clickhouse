defmodule AshClickhouse.Test.Migration.EventsByDay do
  @moduledoc "Destination table a materialized view writes into."

  use Ash.Resource,
    domain: AshClickhouse.Test.Migration.Domain,
    data_layer: AshClickhouse.DataLayer

  resource do
    require_primary_key?(false)
  end

  clickhouse do
    table("events_by_day")
    repo(AshClickhouse.TestRepo)
    engine("SummingMergeTree()")
    options("order by day")
  end

  actions do
    defaults([:read])
  end

  attributes do
    attribute(:day, AshClickhouse.Type.ChDate, public?: true)
    attribute(:events, AshClickhouse.Type.ChUint64, public?: true)
  end
end
