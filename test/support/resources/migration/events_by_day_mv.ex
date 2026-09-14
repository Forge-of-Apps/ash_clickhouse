defmodule AshClickhouse.Test.Migration.EventsByDayMv do
  @moduledoc """
  Materialized view writing into a table it does not own, so redefining it
  costs nothing.
  """

  use Ash.Resource,
    domain: AshClickhouse.Test.Migration.Domain,
    data_layer: AshClickhouse.DataLayer

  import Ecto.Query

  resource do
    require_primary_key?(false)
  end

  clickhouse do
    table("events_by_day_mv")
    repo(AshClickhouse.TestRepo)

    materialized_view do
      source(AshClickhouse.Test.Migration.Event)
      to(AshClickhouse.Test.Migration.EventsByDay)

      query(fn events ->
        from(e in events,
          group_by: selected_as(:day),
          select: %{
            day: selected_as(fragment("toDate(?)", e.at), :day),
            events: selected_as(count(), :events)
          }
        )
      end)
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
