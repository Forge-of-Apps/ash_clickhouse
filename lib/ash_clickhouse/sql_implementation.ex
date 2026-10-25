defmodule AshClickhouse.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

  alias Ash.Query.Function.Ago
  alias Ash.Query.Function.DateAdd
  alias Ash.Query.Function.DateTimeAdd
  alias Ash.Query.Function.Fragment
  alias Ash.Query.Function.FromNow
  alias Ash.Query.Function.GetPath
  alias Ash.Query.Ref
  alias AshClickhouse.DataLayer.Info
  alias AshClickhouse

  @duration_names Ash.Type.DurationName.values()

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
  def expr(
        query,
        %GetPath{
          arguments: [%Ref{attribute: %{type: type, constraints: constraints}} = ref, path],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      )
      when is_list(path) do
    if json?(Ash.Type.storage_type(type, constraints)) do
      subcolumn =
        Enum.map_join(path, fn
          segment when is_atom(segment) or is_binary(segment) ->
            ".`" <> String.replace(to_string(segment), ["\\", "`"], &("\\" <> &1)) <> "`"

          segment ->
            raise ArgumentError,
                  "#{inspect(segment)} in the path #{inspect(path)}: a ClickHouse JSON path names object keys only"
        end)

      {dynamic, acc} =
        AshSql.Expr.dynamic_expr(
          query,
          %Fragment{embedded?: pred_embedded?, arguments: [expr: ref, raw: subcolumn]},
          bindings,
          embedded?,
          nil,
          acc
        )

      {:ok, dynamic, acc}
    else
      :error
    end
  end

  def expr(query, %function{embedded?: pred_embedded?} = expr, bindings, embedded?, acc, _type)
      when function in [Ago, FromNow, DateTimeAdd, DateAdd] do
    now = get_in(query.__ash_bindings__, [:context, :private, :as_of]) || DateTime.utc_now()
    arguments = if nil in expr.arguments, do: [raw: "NULL"], else: shifted(expr, now)

    {dynamic, acc} =
      AshSql.Expr.dynamic_expr(
        query,
        %Fragment{embedded?: pred_embedded?, arguments: arguments},
        bindings,
        embedded?,
        nil,
        acc
      )

    {:ok, dynamic, acc}
  end

  def expr(_query, _expr, _bindings, _embedded?, _acc, _type), do: :error

  defp shifted(%Ago{arguments: arguments}, now), do: in_utc(now, steps("-", arguments))

  defp shifted(%FromNow{arguments: arguments}, now), do: in_utc(now, steps("+", arguments))

  defp shifted(%DateTimeAdd{arguments: [datetime | arguments]}, _now),
    do: in_utc(datetime, steps("+", arguments))

  defp shifted(%DateAdd{arguments: [date | arguments]}, _now) do
    start = [raw: "toDateTime64(", expr: date, raw: ", 0, 'UTC')"]
    [raw: "toDate32("] ++ Enum.reduce(steps("+", arguments), start, &step/2) ++ [raw: ")"]
  end

  defp in_utc(datetime, steps),
    do: Enum.reduce(steps, [raw: "toTimeZone(", expr: datetime, raw: ", 'UTC')"], &step/2)

  defp steps(operator, [amount, unit]), do: [{operator, amount, unit}]

  defp steps(operator, [%Duration{} = duration]) do
    [
      month: duration.year * 12 + duration.month,
      week: duration.week,
      day: duration.day,
      hour: duration.hour,
      minute: duration.minute,
      second: duration.second,
      microsecond: elem(duration.microsecond, 0)
    ]
    |> Enum.reject(&match?({_unit, 0}, &1))
    |> Enum.map(fn {unit, amount} -> {operator, amount, unit} end)
  end

  defp steps(_operator, [duration]) do
    raise ArgumentError,
          "ClickHouse has no value for a Duration, so a date or time can only be shifted by one known when the query is built, got: #{inspect(duration)}"
  end

  defp step({operator, amount, unit}, value) when unit in @duration_names do
    [raw: "("] ++
      value ++
      [
        raw: " #{operator} toInterval#{Macro.camelize(Atom.to_string(unit))}(",
        expr: amount,
        raw: "))"
      ]
  end

  defp step({_operator, _amount, unit}, _value) do
    raise ArgumentError,
          "ClickHouse names the unit of an interval in the query, so it must be known when the query is built, got: #{inspect(unit)}"
  end

  defp json?({:parameterized, {Ch, ch_type}}) when ch_type in [:json, {:nullable, :json}],
    do: true

  defp json?({:parameterized, {Ch, "JSON(" <> _typed_paths}}), do: true
  defp json?({:parameterized, {Ch, "Nullable(JSON(" <> _typed_paths}}), do: true
  defp json?(_storage_type), do: false

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
