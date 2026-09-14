defmodule AshClickhouse.Type.ChIPv4 do
  use Ash.Type
  require AshClickhouse.Type.Helper

  @constraints [
    nullable?: [
      type: :boolean,
      default: false,
      doc: "Whether the IPv4 can be null: Nullable(IPv4)"
    ],
    low_cardinality?: [
      type: :boolean,
      default: false,
      doc: "Whether the IPv4 is a low cardinality type: LowCardinality(IPv4)"
    ]
  ]

  @moduledoc """
  Represents an IPv4 address.

  Registered as `:ch_ipv4` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  defp ch_type(constraints) do
    Ch.Types.ipv4()
    |> maybe_nullable(constraints[:nullable?])
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type
  @impl true
  def constraints, do: @constraints

  @impl true
  def cast_input(value, constraints) do
    Ch.cast(value, ch_type(constraints))
  end

  @impl true
  def matches_type?(nil, _constraints), do: false

  def matches_type?(value, constraints) do
    case Ch.cast(value, ch_type(constraints)) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @impl true
  def cast_stored(value, constraints) do
    Ch.load(value, nil, ch_type(constraints))
  end

  @impl true
  def dump_to_native(value, constraints) do
    Ch.dump(value, nil, ch_type(constraints))
  end

  @impl true
  def generator(_constraints) do
    StreamData.integer(0..255)
    |> StreamData.bind(fn _ ->
      StreamData.tuple({
        StreamData.integer(0..255),
        StreamData.integer(1..254),
        StreamData.integer(1..254),
        StreamData.integer(1..254)
      })
    end)
  end

  @impl true
  def equal?(value1, value2) do
    cast_input(value1, []) == cast_input(value2, [])
  end
end
