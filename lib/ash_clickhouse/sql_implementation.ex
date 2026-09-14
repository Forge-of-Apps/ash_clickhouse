defmodule AshClickhouse.SqlImplementation do
  use AshSql.Implementation

  alias AshClickhouse.DataLayer.Info

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
