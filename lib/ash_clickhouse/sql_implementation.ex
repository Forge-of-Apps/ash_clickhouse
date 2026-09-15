defmodule AshClickhouse.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

  alias AshClickhouse.DataLayer.Info
  alias AshClickhouse

  # @callback expr(Ecto.Query.t(), Ash.Expr.t(), map, boolean, AshSql.Expr.ExprInfo.t(), term) ::
  #             {:ok, term, AshSql.Expr.ExprInfo.t()} | {:error, term} | :error

  # @callback parameterized_type(
  #             Ash.Type.t() | Ecto.Type.t(),
  #             constraints :: Keyword.t()
  #           ) ::
  #             term

  # @callback storage_type(resource :: Ash.Resource.t(), field :: atom()) :: nil | term

  # @callback determine_types(module, list(term)) :: {list(term), term} | list(term)
  # @callback determine_types(module, list(term), returns :: term) ::
  #             {list(term), term} | list(term)

  # @callback list_aggregate(Ash.Resource.t()) :: String.t() | nil

  # @callback multicolumn_distinct?() :: boolean

  # @callback manual_relationship_function() :: atom
  # @callback manual_relationship_subquery_function() :: atom

  # @callback require_ash_functions_for_or_and_and?() :: boolean
  # @callback require_extension_for_citext() :: {true, String.t()} | false
  # @callback strpos_function() :: String.t()

  @impl true
  def table(resource), do: Info.table(resource)

  @impl true
  def schema(resource), do: Info.schema(resource)

  @impl true
  def repo(resource, kind), do: Info.repo(resource, kind)

  @impl true
  def simple_join_first_aggregates(resource), do: Info.simple_join_first_aggregates(resource)

  @impl true
  def list_aggregate(_resource), do: "any_value"

  @impl true
  def ilike?(), do: true

  @impl true
  def manual_relationship_function(), do: :ash_clickhouse_join

  @impl true
  def manual_relationship_subquery_function(), do: :ash_clickhouse_subquery

  @impl true
  def parameterized_type(type, _constraints), do: type

  @impl true
  def type_expr(expr, _type), do: expr

  @impl true
  def determine_types(mod, args, returns \\ nil) do
    returns =
      case returns do
        {:parameterized, _} -> nil
        {:array, {:parameterized, _}} -> nil
        {:array, {type, constraints}} when type != :array -> {type, [items: constraints]}
        {:array, _} -> nil
        {type, constraints} -> {type, constraints}
        other -> other
      end

    {types, new_returns} = Ash.Expr.determine_types(mod, args, returns)

    {types, new_returns || returns}
  end
end
