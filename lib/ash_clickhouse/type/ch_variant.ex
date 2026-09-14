defmodule AshClickhouse.Type.ChVariant do
  use Ash.Type
  require AshClickhouse.Type.Helper

  @constraints [
    types: [
      type: {:list, :any},
      doc: """
      The types of the variant.

      The types can be atoms or keyword lists.

      Example:

      ```elixir
      attribute :variant_col, :ch_variant do
        constraints types: [
          :ch_string,
          :ch_int32,
          :ch_bool,
          ch_map: [
            key_type: :ch_string,
            value_type: [ch_string: [nullable?: true]]
          ]
        ]
      end
      ```
      """
    ]
  ]

  @moduledoc """
  Represents a JSON, with configurable nullable.

  Registered as `:ch_variant` where short type names are configured (see
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
    constraints[:types]
    |> Enum.map(&get_type/1)
    |> Ch.Types.variant()
  end

  defp get_type({type, constraints}) when is_atom(type) and is_list(constraints) do
    Ash.Type.get_type(type).ch_type(constraints)
  end

  defp get_type(type) when is_atom(type) do
    Ash.Type.get_type(type).ch_type([])
  end

  def coerce(value, constraints), do: cast_input(value, constraints)

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(value, constraints), do: Ch.cast(value, ch_type(constraints))

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, constraints), do: Ch.load(value, nil, ch_type(constraints))

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, constraints), do: Ch.dump(value, nil, ch_type(constraints))
end
