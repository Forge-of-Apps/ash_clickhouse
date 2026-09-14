defmodule AshClickhouse.Type.ChTime64 do
  @constraints [
    precision: [
      type: :integer,
      required: true,
      doc: "The precision in Time64(precision), in microseconds"
    ],
    nullable?: [
      type: :boolean,
      default: false,
      doc: "If true, the value is stored as a Nullable(Time64(precision))"
    ]
  ]
  @moduledoc """
  Represents a time in the database, with a 'microsecond' precision

  Registered as `:ch_time64` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """
  use Ash.Type
  require AshClickhouse.Type.Helper

  AshClickhouse.Type.Helper.graphql_type(__MODULE__, :ch_time64, :time)

  @impl true
  def constraints, do: @constraints

  @impl true
  @spec storage_type(nonempty_maybe_improper_list()) :: any()
  def storage_type([{:precision, :microsecond} | _]) do
    :time_usec
  end

  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    Ch.Types.time64(constraints[:precision])
    |> maybe_nullable(constraints[:nullable?])
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  @impl true
  def generator(_constraints) do
    # Waiting on blessed date/datetime generators in stream data
    # https://github.com/whatyouhide/stream_data/pull/161/files
    StreamData.constant(Time.utc_now())
  end

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(%Time{microsecond: {_, _} = microseconds} = time, constraints)
      when microseconds != {0, 0} do
    cast_input(%{time | microsecond: {0, 0}}, constraints)
  end

  def cast_input(%Time{microsecond: nil} = time, constraints) do
    cast_input(%{time | microsecond: {0, 6}}, constraints)
  end

  def cast_input(value, constraints) do
    Ch.cast(value, ch_type(constraints))
  end

  @impl true
  def matches_type?(%Time{}, _), do: true
  def matches_type?(_, _), do: false

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
