defmodule AshClickhouse.Type.ChBool do
  @constraints [
    nullable?: [
      type: :boolean,
      default: false,
      doc: "Whether the boolean can be null: Nullable(Boolean)"
    ],
    low_cardinality?: [
      type: :boolean,
      default: false,
      doc: "Whether the boolean is a low cardinality type: LowCardinality(Boolean)"
    ]
  ]
  @moduledoc """
  Represents a boolean.

  Registered as `:ch_bool` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """
  use Ash.Type
  require AshClickhouse.Type.Helper

  AshClickhouse.Type.Helper.graphql_type(__MODULE__, :ch_bool, :boolean)

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    Ch.Types.boolean()
    |> maybe_nullable(constraints[:nullable?])
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  @impl true
  def generator(_constraints) do
    StreamData.boolean()
  end

  @impl true
  def cast_input(value, constraints) do
    Ch.cast(value, ch_type(constraints))
  end

  @impl true
  def matches_type?(v, _) do
    is_boolean(v)
  end

  @impl true
  def cast_atomic(new_value, _constraints) do
    {:atomic, new_value}
  end

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, constraints) when is_boolean(value) do
    Ch.load(value, nil, ch_type(constraints))
  end

  def cast_stored(1, constraints), do: Ch.load(true, nil, ch_type(constraints))
  def cast_stored(0, constraints), do: Ch.load(false, nil, ch_type(constraints))

  def cast_stored(value, _constraints) when is_binary(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> :error
    end
  end

  def cast_stored(_, _), do: :error

  @impl true

  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(value, constraints) do
    Ch.dump(value, nil, ch_type(constraints))
  end
end
