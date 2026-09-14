defmodule AshClickhouse.Test.Migration.RawSelect do
  @moduledoc "Materialized view whose SELECT is raw SQL rather than an Ecto.Query."

  use Ash.Resource,
    domain: AshClickhouse.Test.Migration.Domain,
    data_layer: AshClickhouse.DataLayer

  resource do
    require_primary_key?(false)
  end

  clickhouse do
    table("raw_select_mv")
    repo(AshClickhouse.TestRepo)

    materialized_view do
      source("events")
      to(AshClickhouse.Test.Migration.EventsByDay)
      select("SELECT toDate(at) AS day, count() AS events FROM events GROUP BY day")
    end
  end

  actions do
    defaults([:read])
  end

  attributes do
    attribute(:day, AshClickhouse.Type.ChDate, public?: true)
    attribute(:events, AshClickhouse.Type.ChUint64, public?: true)
  end
end
