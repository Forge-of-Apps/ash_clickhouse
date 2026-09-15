defmodule AshClickhouse.ManualRelationship do
  @moduledoc """
  Implemented by a manual relationship that can be joined in ClickHouse.

  Ash cannot join a manual relationship on its own — the module decides what
  the join is. Implement this alongside `Ash.Resource.ManualRelationship` and
  the data layer will fold `ash_clickhouse_join/5` into the query rather than
  loading the relationship separately.
  """

  @callback ash_clickhouse_join(
              source_query :: Ecto.Query.t(),
              opts :: Keyword.t(),
              current_binding :: term,
              destination_binding :: term,
              type :: :inner | :left,
              destination_query :: Ecto.Query.t()
            ) :: {:ok, Ecto.Query.t()} | {:error, term}

  @callback ash_clickhouse_subquery(
              opts :: Keyword.t(),
              current_binding :: term,
              destination_binding :: term,
              destination_query :: Ecto.Query.t()
            ) :: {:ok, Ecto.Query.t()} | {:error, term}

  defmacro __using__(_) do
    quote do
      @behaviour AshClickhouse.ManualRelationship
    end
  end
end
