defmodule AshClickhouse.Type.ChMap do
  @constraints [
    key_type: [
      type: {:or, [:atom, :keyword_list]},
      required: true,
      doc: """
      The type of the keys in the map.
      """
    ],
    value_type: [
      type: {:or, [:atom, :keyword_list]},
      required: true,
      doc: """
      The type of the values in the map.
      """
    ],
    fields: [
      type: {:list, :any},
      doc: """
      The fields of the map.
      Example: [:foo, :bar, :baz]
      """
    ]
  ]

  @moduledoc """
  Represents a map stored in the database.

  In postgres, for example, this represents binary encoded json

  Registered as `:ch_map` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """
  use Ash.Type

  @impl true
  def constraints, do: @constraints

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    ch_key_type = get_ch_type(constraints[:key_type])
    ch_value_type = get_ch_type(constraints[:value_type])

    Ch.Types.map(ch_key_type, ch_value_type)
    |> maybe_nullable(constraints[:nullable?])
  end

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  defp get_ch_type(nil), do: raise("key_type and value_type must be a valid Ash type")

  defp get_ch_type(type) when is_atom(type) do
    Ash.Type.get_type(type).ch_type([])
  end

  defp get_ch_type([{type, constraints}]) when is_atom(type) and is_list(constraints) do
    Ash.Type.get_type(type).ch_type(constraints)
  end

  defp get_ash_type(nil), do: raise("key_type and value_type must be a valid Ash type")

  defp get_ash_type(type) when is_atom(type) do
    {Ash.Type.get_type(type), []}
  end

  defp get_ash_type([{type, constraints}]) when is_atom(type) and is_list(constraints) do
    {Ash.Type.get_type(type), constraints}
  end

  @impl true
  def matches_type?(v, _constraints) do
    is_map(v)
  end

  @impl true
  def cast_input("", _), do: {:ok, nil}

  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(value, constraints) when is_binary(value) do
    case Ash.Helpers.json_module().decode(value) do
      {:ok, value} ->
        cast_input(value, constraints)

      _ ->
        :error
    end
  end

  def cast_input(value, _) when is_map(value), do: {:ok, value}
  def cast_input(_, _), do: :error

  @impl true

  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, constraints) when is_map(value) do
    Ch.cast(value, ch_type(constraints))
  end

  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _) when is_map(value), do: {:ok, value}
  def dump_to_native(_, _), do: :error

  @impl true
  def apply_constraints(nil, _constraints), do: {:ok, nil}

  def apply_constraints(value, constraints) do
    check_fields(value, constraints)
  end

  @impl true
  def generator(constraints) do
    {field_type, field_contraints} = get_ash_type(constraints[:key_type])
    {value_type, value_constraints} = get_ash_type(constraints[:value_type])

    generate = fn type, contraints ->
      type
      |> Ash.Type.generator(contraints)
      |> StreamData.filter(fn item ->
        with {:ok, value} <- Ash.Type.cast_input(type, item, contraints),
             {:ok, nil} <-
               Ash.Type.apply_constraints(type, value, contraints) do
          false
        else
          _ ->
            true
        end
      end)
    end

    if constraints[:fields] do
      Map.new(constraints[:fields], fn field ->
        generator = generate.(value_type, value_constraints)

        {field, generator}
      end)
      |> Ash.Generator.mixed_map([])
    else
      field_generator = generate.(field_type, field_contraints)
      value_generator = generate.(value_type, value_constraints)

      StreamData.list_of(
        StreamData.fixed_map(%{
          key: field_generator,
          value: value_generator
        }),
        max_length: 5
      )
      |> StreamData.map(fn pairs ->
        Map.new(pairs, fn %{key: key, value: value} ->
          {key, value}
        end)
      end)
    end
  end

  defp check_fields(value, constraints) do
    {errors, result} =
      if constraints[:fields] do
        Enum.reduce(constraints[:fields], {[], %{}}, fn
          field, {errors_acc, result_acc} ->
            case fetch_field(value, field) do
              {:ok, field_value} ->
                case check_field(result_acc, field, field_value, constraints) do
                  {:ok, updated_result} ->
                    {errors_acc, updated_result}

                  {:error, field_errors} ->
                    {errors_acc ++ field_errors, result_acc}
                end

              :error ->
                field_error = [message: "field must be present", field: field]
                {errors_acc ++ [field_error], result_acc}
            end
        end)
      else
        Enum.reduce(value, {[], %{}}, fn {field, value}, {errors_acc, result_acc} ->
          case check_field(result_acc, field, value, constraints) do
            {:ok, updated_result} ->
              {errors_acc, updated_result}

            {:error, field_errors} ->
              {errors_acc ++ field_errors, result_acc}
          end
        end)
      end

    case errors do
      [] -> {:ok, result}
      _ -> {:error, errors}
    end
  end

  defp check_field(result, field, field_value, constraints) do
    with {:ok, field} <- check_field_type(field, constraints[:key_type]),
         {:ok, value} <- check_field_value_type(field, field_value, constraints[:value_type]) do
      {:ok, Map.put(result, field, value)}
    else
      error -> error
    end
  end

  defp check_field_type(field, ch_type) do
    {type, constraints} = get_ash_type(ch_type)

    case Ash.Type.cast_input(type, field, constraints) do
      {:ok, casted_field} ->
        case Ash.Type.apply_constraints(type, casted_field, constraints) do
          {:ok, final_field} ->
            {:ok, final_field}

          {:error, errors} ->
            {:error,
             Ash.Type.CompositeTypeHelpers.convert_constraint_errors_to_keyword_lists(
               errors,
               field
             )}
        end

      {:error, error} ->
        {:error, [error]}

      :error ->
        {:error, [[message: "invalid value", field: field]]}
    end
  end

  defp check_field_value_type(field, field_value, ch_type) do
    {type, constraints} = get_ash_type(ch_type)

    case Ash.Type.cast_input(type, field_value, constraints) do
      {:ok, casted_field_value} ->
        case Ash.Type.apply_constraints(type, casted_field_value, constraints) do
          {:ok, final_field_value} ->
            {:ok, final_field_value}

          {:error, errors} ->
            {:error,
             Ash.Type.CompositeTypeHelpers.convert_constraint_errors_to_keyword_lists(
               errors,
               field
             )}
        end

      {:error, message} ->
        {:error, [[message: message, field: field]]}

      :error ->
        {:error, [[message: "is invalid", field: field]]}
    end
  end

  defp fetch_field(map, atom) when is_atom(atom) do
    case Map.fetch(map, atom) do
      {:ok, value} -> {:ok, value}
      :error -> fetch_field(map, to_string(atom))
    end
  end

  defp fetch_field(map, key), do: Map.fetch(map, key)
end
