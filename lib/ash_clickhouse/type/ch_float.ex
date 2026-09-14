for size <- [32, 64] do
  module_name = Module.concat([AshClickhouse.Type, "ChFloat#{size}"])
  function_name = String.to_atom("f#{size}")

  defmodule module_name do
    @constraints [
      max: [
        type: {:custom, __MODULE__, :float, []},
        doc: "Enforces a maximum on the value"
      ],
      min: [
        type: {:custom, __MODULE__, :float, []},
        doc: "Enforces a minimum on the value"
      ],
      greater_than: [
        type: {:custom, __MODULE__, :float, []},
        doc: "Enforces a minimum on the value (exclusive)"
      ],
      less_than: [
        type: {:custom, __MODULE__, :float, []},
        doc: "Enforces a maximum on the value (exclusive)"
      ],
      low_cardinality?: [
        type: :boolean,
        doc: "If true, the value is stored as a LowCardinality type",
        default: false
      ],
      nullable?: [
        type: :boolean,
        doc: "If true, the value is stored as a Nullable type",
        default: false
      ]
    ]

    import Ash.Expr

    @moduledoc """
    Represents a float#{size} (floating point number)

    Registered as `:ch_float#{size}` where short type names are configured (see
    `AshClickhouse`); an attribute can always name this module instead.

    ### Constraints

    #{Spark.Options.docs(@constraints)}
    """

    use Ash.Type
    require AshClickhouse.Type.Helper

    AshClickhouse.Type.Helper.graphql_type(__MODULE__, :"ch_float#{unquote(size)}", :float)

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

    defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
    defp maybe_nullable(type, _), do: type

    defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
    defp maybe_low_cardinality(type, _), do: type

    @impl true
    def constraints, do: @constraints

    @doc false
    def float(value) do
      case cast_input(value, []) do
        {:ok, float} ->
          {:ok, float}

        :error ->
          {:error, "cannot be casted to float"}
      end
    end

    @impl true
    def matches_type?(v, _) do
      is_float(v)
    end

    @impl true
    def generator(constraints) do
      [
        min: constraints[:min] || constraints[:greater_than] || -1.0e10,
        max: constraints[:max] || constraints[:less_than] || 1.0e10
      ]
      |> StreamData.float()
      |> StreamData.filter(fn value ->
        (!constraints[:less_than] || value < constraints[:less_than]) &&
          (!constraints[:greater_than] || value > constraints[:greater_than])
      end)
    end

    @impl true
    def apply_constraints(nil, _), do: {:ok, nil}

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

          {:less_than, less_than}, errors ->
            if value < less_than do
              errors
            else
              [[message: "must be less than %{less_than}", less_than: less_than] | errors]
            end

          {:greater_than, greater_than}, errors ->
            if value > greater_than do
              errors
            else
              [
                [message: "must be more than %{greater_than}", greater_than: greater_than]
                | errors
              ]
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
    def cast_input(nil, _), do: {:ok, nil}

    def cast_input(value, constraints) do
      Ch.cast(value, ch_type(constraints))
    end

    @impl true
    def cast_stored(nil, _), do: {:ok, nil}

    def cast_stored(value, constraints) do
      Ch.load(value, nil, ch_type(constraints))
    end

    @impl true
    def cast_atomic(expr, _constraints) do
      {:atomic, expr}
    end

    def apply_atomic_constraints(expr, constraints) do
      expr =
        Enum.reduce(constraints, expr, fn
          {:max, max}, expr ->
            expr(
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

          {:min, min}, expr ->
            expr(
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

          {:less_than, less_than}, expr ->
            expr(
              if ^expr < ^less_than do
                ^expr
              else
                error(
                  Ash.Error.Changes.InvalidChanges,
                  message: "must be greater than %{less_than}",
                  vars: %{less_than: ^less_than}
                )
              end
            )

          {:greater_than, greater_than}, expr ->
            expr(
              if ^expr > ^greater_than do
                ^expr
              else
                error(
                  Ash.Error.Changes.InvalidChanges,
                  message: "must be greater than %{greater_than}",
                  vars: %{greater_than: ^greater_than}
                )
              end
            )
        end)

      {:ok, expr}
    end

    @impl true
    def dump_to_native(nil, _), do: {:ok, nil}

    def dump_to_native(value, constraints) do
      Ch.dump(value, nil, ch_type(constraints))
    end
  end
end
