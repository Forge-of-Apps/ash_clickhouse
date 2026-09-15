defmodule AshClickhouse.Type.ChDate32 do
  use Ash.Type
  require AshClickhouse.Type.Helper

  @constraints [
    nullable?: [
      type: :boolean,
      default: false,
      doc: "Whether the date can be null: Nullable(Date)"
    ],
    low_cardinality?: [
      type: :boolean,
      default: false,
      doc: "Whether to use LowCardinality optimization"
    ]
  ]

  @moduledoc """
  Represents a Date, with configurable nullable.

  Registered as `:ch_date32` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """

  AshClickhouse.Type.Helper.graphql_type(__MODULE__, :ch_date32, :date)

  @impl true
  def constraints, do: @constraints

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    Ch.Types.date32()
    |> maybe_nullable(constraints[:nullable?])
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type

  @impl true
  def generator(_constraints) do
    # Waiting on blessed date/datetime generators in stream data
    # https://github.com/whatyouhide/stream_data/pull/161/files
    StreamData.constant(Date.utc_today())
  end

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(value, constraints) do
    Ch.cast(value, ch_type(constraints))
  end

  @impl true
  def matches_type?(%Date{}, _), do: true

  def matches_type?(value, constraints) do
    case Ch.cast(value, ch_type(constraints)) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @impl true
  def cast_atomic(new_value, _constraints) do
    {:atomic, new_value}
  end

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, constraints) when is_binary(value) do
    cast_input(value, constraints)
  end

  def cast_stored(value, constraints) do
    Ch.load(value, nil, ch_type(constraints))
  end

  @impl true

  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(value, constraints) do
    Ch.dump(value, nil, ch_type(constraints))
  end
end
