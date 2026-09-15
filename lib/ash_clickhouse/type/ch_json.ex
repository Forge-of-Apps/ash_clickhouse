defmodule AshClickhouse.Type.ChJSON do
  use Ash.Type
  require AshClickhouse.Type.Helper

  @constraints [
    nullable?: [
      type: :boolean,
      default: false,
      doc: "Whether the JSON can be null: Nullable(JSON)"
    ]
  ]

  @moduledoc """
  Represents a JSON, with configurable nullable.

  Registered as `:ch_json` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """

  AshClickhouse.Type.Helper.graphql_type(__MODULE__, :ch_json, :json)

  @impl true
  def constraints, do: @constraints

  @impl true
  def storage_type(constraints), do: {:parameterized, {Ch, ch_type(constraints)}}

  def ch_type(constraints) do
    Ch.Types.json()
    |> maybe_nullable(constraints[:nullable?])
  end

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  def coerce(value, constraints), do: cast_input(value, constraints)

  @impl true
  def matches_type?(nil, _constraints), do: false

  def matches_type?(value, constraints) do
    case cast_input(value, constraints) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, constraints) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} ->
        Ch.cast(decoded, ch_type(constraints))

      {:error, _rreason} ->
        :error
    end
  end

  def cast_input(value, constraints) do
    case Jason.encode(value) do
      {:ok, json} ->
        json
        |> Jason.decode!()
        |> Ch.cast(ch_type(constraints))

      {:error, _reason} ->
        :error
    end
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, constraints) do
    case cast_input(value, constraints) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, constraints), do: Ch.dump(value, nil, ch_type(constraints))
end
