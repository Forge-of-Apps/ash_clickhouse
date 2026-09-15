defmodule AshClickhouse.MaterializedView do
  @moduledoc """
  Turns a resource's `materialized_view` block into the SELECT its DDL carries.

  The block's `query` is a function of the source table name returning an
  `Ecto.Query`, which is planned and rendered through `ecto_ch` — no repo has
  to be running, because a view's SELECT is DDL rather than a query anyone
  executes. `select` takes raw SQL instead, for the statements Ecto cannot
  express.

  ClickHouse matches a view's output to its destination table **by column
  name**, filling anything unmatched with that column's default rather than
  failing, so an alias is not decoration: it is the only thing connecting the
  two. Name every selected column with `selected_as/2` — an unaliased one
  reaches ClickHouse as `toDate(at)` and matches nothing — and this module
  refuses a name the destination does not have, which is the typo that would
  otherwise cost a column of data silently.

      materialized_view do
        source MyApp.Event
        to MyApp.EventsByDay

        query fn events ->
          from e in events,
            group_by: selected_as(:day),
            select: %{
              day: selected_as(fragment("toDate(?)", e.at), :day),
              events: selected_as(count(), :events)
            }
        end
      end
  """

  @adapter Ecto.Adapters.ClickHouse

  @doc """
  The SELECT for a view, as `{sql, aliases}`.

  `aliases` is the list of names the SELECT gives its columns, empty for raw
  `select` SQL, which this module does not parse.
  """
  def select_sql(_source, nil, select) when is_binary(select), do: {select, []}

  def select_sql(source, query, nil) when is_function(query, 1) do
    ecto_query = query.(source)

    {planned, params, _key} = Ecto.Query.Planner.plan(ecto_query, :all, @adapter)

    if params != [] do
      raise """
      The query for the materialized view over #{source} carries #{length(params)} \
      bound parameter(s), and a view's SELECT is DDL: ClickHouse stores it once and \
      there is nothing to bind them to later.

      Write the values into the query itself rather than pinning them, or reach \
      for `fragment/1` where a literal will not do.
      """
    end

    {normalized, _} = Ecto.Query.Planner.normalize(planned, :all, @adapter, 0)

    {normalized |> @adapter.Connection.all() |> IO.iodata_to_binary(), aliases(normalized)}
  end

  @doc """
  Refuses a view whose SELECT names a column its destination does not have.

  A destination column the SELECT skips is left alone: taking its default is a
  legitimate thing to want, whereas a name matching nothing never is.
  """
  def validate_aliases!(view_table, aliases, destination_columns) do
    case Enum.reject(aliases, &(&1 in destination_columns)) do
      [] ->
        :ok

      unmatched ->
        raise """
        #{view_table} selects #{Enum.map_join(unmatched, ", ", &"`#{&1}`")}, which its \
        destination table does not have.

        ClickHouse matches a view's output to its destination by name and defaults \
        whatever is unmatched, so these columns would be computed on every insert and \
        then dropped. Destination columns: #{Enum.map_join(destination_columns, ", ", &"`#{&1}`")}.
        """
    end
  end

  defp aliases(%{select: %{expr: expr}}) do
    {_, found} =
      Macro.prewalk(expr, [], fn
        {:selected_as, _, [_inner, name]} = node, acc -> {node, [to_string(name) | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(found)
  end

  defp aliases(_query), do: []
end
