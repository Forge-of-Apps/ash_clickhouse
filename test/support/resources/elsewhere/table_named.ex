defmodule AshClickhouse.Test.Elsewhere.TableNamed do
  @moduledoc """
  Materialized view naming a table of another domain by its bare name, which
  its own domain cannot resolve.
  """

  use Ash.Resource,
    domain: AshClickhouse.Test.Elsewhere.Domain,
    data_layer: AshClickhouse.DataLayer

  import Ecto.Query

  resource do
    require_primary_key?(false)
  end

  clickhouse do
    table("events_by_day_by_name_mv")
    repo(AshClickhouse.TestRepo)

    materialized_view do
      source(AshClickhouse.Test.Migration.Event)
      to("events_by_day")

      query(fn events ->
        from(e in events,
          group_by: selected_as(:day),
          select: %{day: selected_as(fragment("toDate(?)", e.at), :day)}
        )
      end)
    end
  end

  actions do
    defaults([:read])
  end

  attributes do
    attribute(:day, AshClickhouse.Type.ChDate, public?: true)
  end
end
