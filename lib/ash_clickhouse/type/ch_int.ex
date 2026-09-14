for size <- [8, 16, 32, 64, 128, 256] do
  module_name = Module.concat([AshClickhouse.Type, "ChInt#{size}"])
  function_name = String.to_atom("i#{size}")

  defmodule module_name do
    @constraints [
      max: [
        type: {:custom, __MODULE__, :integer, []},
        doc: "Enforces a maximum on the value"
      ],
      min: [
        type: {:custom, __MODULE__, :integer, []},
        doc: "Enforces a minimum on the value"
      ],
      low_cardinality?: [
        type: :boolean,
        doc: "If true, the value is stored as a LowCardinality(Integer)",
        default: false
      ],
      nullable?: [
        type: :boolean,
        doc: "If true, the value is stored as a Nullable(Integer)",
        default: false
      ]
    ]
    @moduledoc """
    Represents a simple integer

    Registered as `:ch_int#{size}` where short type names are configured (see
    `AshClickhouse`); an attribute can always name this module instead.

    ### Constraints

    #{Spark.Options.docs(@constraints)}
    """
    use Ash.Type

    require Ash.Expr
    require AshClickhouse.Type.Helper

    if size in [8, 16, 32] do
      AshClickhouse.Type.Helper.graphql_type(__MODULE__, :"ch_int#{unquote(size)}", :integer)
    else
      AshClickhouse.Type.Helper.graphql_type(__MODULE__, :"ch_int#{unquote(size)}", :string)
    end

    @impl true
    def matches_type?(v, _) do
      is_integer(v)
    end

    @impl true
    def cast_atomic(expr, _) do
      {:atomic, expr}
    end

    @impl true
    def apply_atomic_constraints(expr, constraints) do
      expr =
        case {constraints[:max], constraints[:min]} do
          {nil, nil} ->
            expr

          {max, nil} ->
            Ash.Expr.expr(
              if ^expr > ^max do
                error(
                  Ash.Error.Changes.InvalidChanges,
                  message: "must be less than or equal to %{max}",
                  vars: %{max: ^max}
                )
              else
                ^expr
              end
            )

          {nil, min} ->
            Ash.Expr.expr(
              if ^expr < ^min do
                error(
                  Ash.Error.Changes.InvalidChanges,
                  message: "must be greater than or equal to %{min}",
                  vars: %{min: ^min}
                )
              else
                ^expr
              end
            )

          {max, min} ->
            Ash.Expr.expr(
              cond do
                ^expr < ^min ->
                  error(
                    Ash.Error.Changes.InvalidChanges,
                    message: "must be greater than or equal to %{min}",
                    vars: %{min: ^min}
                  )

                ^expr > ^max ->
                  error(
                    Ash.Error.Changes.InvalidChanges,
                    message: "must be less than or equal to %{max}",
                    vars: %{max: ^max}
                  )

                true ->
                  ^expr
              end
            )
        end

      {:ok, expr}
    end

    @impl true
    def storage_type(constraints) do
      {:parameterized, {Ch, ch_type(constraints)}}
    end

    def ch_type(constraints) do
      Ch.Types
      |> apply(unquote(function_name), [])
      |> maybe_nullable(constraints[:nullable?])
      |> maybe_low_cardinality(constraints[:low_cardinality?])
    end

    defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
    defp maybe_low_cardinality(type, _), do: type

    defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
    defp maybe_nullable(type, _), do: type

    @impl true
    def generator(constraints) do
      min = constraints[:min] || -2_147_483_648
      max = constraints[:max] || 2_147_483_647

      StreamData.integer(min..max)
    end

    @impl true
    def constraints, do: @constraints

    @doc false
    def integer(value) when is_integer(value), do: {:ok, value}
    def integer(_), do: {:error, "must be an integer"}

    def apply_constraints(nil, _), do: :ok

    def apply_constraints(value, constraints) do
      errors =
        Enum.reduce(constraints, [], fn
          {:max, max}, errors ->
            if value > max do
              [[message: "must be less than or equal to %{max}", max: max] | errors]
            else
              errors
            end

          {:min, min}, errors ->
            if value < min do
              [[message: "must be more than or equal to %{min}", min: min] | errors]
            else
              errors
            end

          _, errors ->
            errors
        end)

      case errors do
        [] -> {:ok, value}
        errors -> {:error, errors}
      end
    end

    @impl true
    def cast_input(value, constraints) do
      Ch.cast(value, ch_type(constraints))
    end

    @impl true
    def cast_stored(nil, _), do: {:ok, nil}

    def cast_stored(string, constraints) when is_binary(string) do
      case Integer.parse(string) do
        {integer, ""} ->
          cast_stored(integer, constraints)

        _ ->
          :error
      end
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
end
