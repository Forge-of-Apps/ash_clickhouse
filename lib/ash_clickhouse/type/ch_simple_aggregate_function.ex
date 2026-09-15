defmodule AshClickhouse.Type.ChSimpleAggregateFunction do
  use Ash.Type
  require AshClickhouse.Type.Helper

  @constraints [
    function: [
      type: :string,
      doc: "The function to use: SUM, AVG, MIN, MAX, etc.",
      required: true
    ],
    type: [
      type: {:or, [:atom, :keyword_list]},
      doc: "The type of the function: SUM, AVG, MIN, MAX, etc.",
      required: true
    ],
    low_cardinality?: [
      type: :boolean,
      doc: "Whether the function is a low cardinality function",
      required: false
    ]
  ]

  @moduledoc """
  Represents a simple aggregate function.

  Registered as `:ch_simple_aggregate_function` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """

  @impl true
  def constraints, do: @constraints

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    type =
      case constraints[:type] do
        {type, constraints} ->
          Ash.Type.get_type(type).ch_type(constraints)

        type ->
          Ash.Type.get_type(type).ch_type([])
      end

    Ch.Types.simple_aggregate_function(constraints[:function], type)
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type

  def coerce(value, constraints), do: cast_input(value, constraints)

  @impl true
  def cast_input(value, constraints) do
    Ch.cast(value, ch_type(constraints))
  end

  @impl true
  def cast_stored(value, constraints) do
    Ch.load(value, nil, ch_type(constraints))
  end

  @impl true
  def dump_to_native(value, constraints) do
    Ch.dump(value, nil, ch_type(constraints))
  end
end
