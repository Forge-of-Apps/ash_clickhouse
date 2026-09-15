defmodule AshClickhouse.Type.ChDateTime64 do
  @constraints [
    precision: [
      type: :non_neg_integer,
      required: true,
      doc: "The precision in DateTime64(precision), in microseconds"
    ],
    cast_dates_as: [
      type: {:one_of, [:start_of_day, :error]},
      default: :start_of_day
    ],
    timezone: [
      type: :string,
      doc: "The timezone in DateTime64(precision, timezone) e.g. 'UTC'"
    ],
    nullable?: [
      type: :boolean,
      default: false,
      doc: "If true, the value is stored as a Nullable(DateTime64(precision, timezone))"
    ],
    low_cardinality?: [
      type: :boolean,
      default: false,
      doc: "If true, the value is stored as a LowCardinality(DateTime64(precision, timezone))"
    ]
  ]

  @moduledoc """
  Represents a DateTime64, with configurable precision and timezone.

  Registered as `:ch_datetime64` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """

  @beginning_of_day Time.new!(0, 0, 0)

  use Ash.Type
  require AshClickhouse.Type.Helper

  def graphql_type(constraints) do
    case Keyword.get(constraints, :timezone) do
      nil -> :naive_datetime
      _timezone -> :datetime
    end
  end

  def graphql_input_type(constraints) do
    case Keyword.get(constraints, :timezone) do
      nil -> :naive_datetime
      _timezone -> :datetime
    end
  end

  @impl true
  def constraints, do: @constraints

  @impl true
  def cast_atomic(new_value, _constraints) do
    {:atomic, new_value}
  end

  @impl true
  def matches_type?(%DateTime{}, _), do: true

  def matches_type?(value, constraints) when is_binary(value) do
    case Ch.cast(value, ch_type(constraints)) do
      {:ok, _} -> true
      :error -> false
    end
  end

  def matches_type?(_, _), do: false

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    Ch.Types.datetime64(constraints[:precision])
    |> maybe_timezone(constraints[:timezone])
    |> maybe_nullable(constraints[:nullable?])
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_timezone({:datetime64, precision}, timezone) when is_binary(timezone) do
    Ch.Types.datetime64(precision, timezone)
  end

  defp maybe_timezone(type, _), do: type

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type

  @impl true
  def generator(_constraints) do
    # Waiting on blessed date/datetime generators in stream data
    # https://github.com/whatyouhide/stream_data/pull/161/files
    StreamData.constant(DateTime.utc_now())
  end

  @impl true
  def cast_input(%Date{} = date, constraints) do
    case Keyword.get(constraints, :cast_dates_as, :start_of_day) do
      :start_of_day ->
        case DateTime.new(date, @beginning_of_day) do
          {:ok, value} ->
            cast_input(value, constraints)

          _ ->
            {:error, "Date could not be converted to datetime"}
        end

      _ ->
        {:error, "must be a datetime, got a date"}
    end
  end

  def cast_input(value, constraints) do
    case Ch.cast(value, ch_type(constraints)) do
      :error ->
        case Keyword.get(constraints, :cast_dates_as, :start_of_day) do
          :start_of_day ->
            case Ash.Type.cast_input(:date, value, []) do
              {:ok, date} ->
                cast_input(date, constraints)

              _ ->
                {:error, "Could not cast input to datetime"}
            end

          _ ->
            {:error, "must be a datetime, got a date"}
        end

      {:ok, value} ->
        {:ok, value}
    end
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
