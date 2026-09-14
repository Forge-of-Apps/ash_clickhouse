defmodule AshClickhouse.Test.Migration.EventCount do
  @moduledoc """
  Materialized view owning its own storage, so its definition cannot be changed
  without discarding what it has accumulated.
  """

  use Ash.Resource,
    domain: AshClickhouse.Test.Migration.Domain,
    data_layer: AshClickhouse.DataLayer

  import Ecto.Query

  resource do
    require_primary_key?(false)
  end

  clickhouse do
    table("event_count_mv")
    repo(AshClickhouse.TestRepo)
    engine("SummingMergeTree()")
    options("order by name")

    materialized_view do
      source(AshClickhouse.Test.Migration.Event)

      query(fn events ->
        from(e in events,
          group_by: selected_as(:name),
          select: %{
            name: selected_as(e.name, :name),
            total: selected_as(sum(e.amount), :total)
          }
        )
      end)
    end
  end

  actions do
    defaults([:read])
  end

  attributes do
    attribute(:name, AshClickhouse.Type.ChString, public?: true)
    attribute(:total, AshClickhouse.Type.ChUint64, public?: true)
  end
end
