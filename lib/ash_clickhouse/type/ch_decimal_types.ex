for {precision, max_scale} <- [{32, 9}, {64, 18}, {128, 38}, {256, 76}] do
  module_name = Module.concat([AshClickhouse.Type, "ChDecimal#{precision}"])
  function_name = String.to_atom("decimal#{precision}")

  defmodule module_name do
    @constraints [
      scale: [
        type: :non_neg_integer,
        required: true,
        doc: "Enforces a number of significant digits."
      ],
      max: [
        type: {:custom, __MODULE__, :decimal, []},
        doc: "Enforces a maximum on the value"
      ],
      min: [
        type: {:custom, __MODULE__, :decimal, []},
        doc: "Enforces a minimum on the value"
      ],
      greater_than: [
        type: {:custom, __MODULE__, :decimal, []},
        doc: "Enforces a minimum on the value (exclusive)"
      ],
      less_than: [
        type: {:custom, __MODULE__, :decimal, []},
        doc: "Enforces a maximum on the value (exclusive)"
      ],
      nullable?: [
        type: :boolean,
        doc:
          "If true, the value is stored as a Nullable(Decimal(precision)) or Nullable(LowCardinality(Decimal(precision))) if low_cardinality? is true",
        default: false
      ]
    ]

    import Ash.Expr

    @moduledoc """
    Represents a decimal.

    Registered as `:ch_decimal#{precision}` where short type names are configured (see
    `AshClickhouse`); an attribute can always name this module instead.

    ### Constraints

    #{Spark.Options.docs(@constraints)}
    """
    use Ash.Type
    require Decimal
    require AshClickhouse.Type.Helper

    AshClickhouse.Type.Helper.graphql_type(
      __MODULE__,
      :"ch_decimal#{unquote(precision)}",
      :decimal
    )

    @impl true
    def generator(constraints) do
      params =
        constraints
        |> Keyword.take([:min, :max])
        |> Enum.map(fn {key, value} ->
          if Decimal.is_decimal(value) do
            {key, Decimal.to_float(value)}
          else
            {key, value}
          end
        end)

      params
      |> StreamData.float()
      |> StreamData.map(&Decimal.from_float/1)
      #  A second pass filter to account for inaccuracies in the above float -> decimal
      |> StreamData.filter(fn value ->
        !(constraints[:max] && Decimal.gt?(value, constraints[:max])) &&
          (!constraints[:less_than] || Decimal.lt?(value, constraints[:less_than])) &&
          !(constraints[:min] && Decimal.lt?(value, constraints[:min])) &&
          (!constraints[:greater_than] || Decimal.gt?(value, constraints[:greater_than]))
      end)
    end

    @impl true
    def storage_type(constraints) do
      {:parameterized, {Ch, ch_type(constraints)}}
    end

    def ch_type(constraints) do
      if constraints[:scale] > unquote(max_scale) do
        raise """
        The scale constraint for #{unquote(module_name)} cannot be greater than #{unquote(max_scale)}.
        You provided: #{constraints[:scale]}
        """
      end

      Ch.Types
      |> apply(unquote(function_name), [constraints[:scale]])
      |> maybe_nullable(constraints[:nullable?])
    end

    defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
    defp maybe_nullable(type, _), do: type

    @impl true
    def constraints, do: @constraints

    @impl true
    def matches_type?(%Decimal{}, _), do: true
    def matches_type?(_, _), do: false

    @doc false
    def decimal(value) do
      case cast_input(value, []) do
        {:ok, decimal} ->
          {:ok, decimal}

        :error ->
          {:error, "cannot be casted to decimal"}
      end
    end

    @impl true
    def cast_atomic(expr, constraints) do
      cond do
        constraints[:scale] && constraints[:scale] != :arbitrary ->
          {:not_atomic, "cannot atomically validate the `scale` of a decimal with an expression"}

        constraints[:scale] && constraints[:scale] != :arbitrary ->
          {:not_atomic, "cannot atomically validate the `scale` of a decimal with an expression"}

        true ->
          {:atomic, expr}
      end
    end

    def apply_atomic_constraints(expr, constraints) do
      if Ash.Expr.expr?(expr) do
        expr =
          Enum.reduce(constraints, expr, fn
            {:scale, :arbitrary}, expr ->
              expr

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
                    message: "must be less than %{less_than}",
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
      else
        apply_constraints(expr, constraints)
      end
    end

    @impl true
    def apply_constraints(nil, _), do: {:ok, nil}

    def apply_constraints(value, constraints) do
      errors =
        Enum.reduce(constraints, [], fn
          {:max, max}, errors ->
            if Decimal.compare(value, max) == :gt do
              [[message: "must be less than or equal to %{max}", max: max] | errors]
            else
              errors
            end

          {:min, min}, errors ->
            if Decimal.compare(value, min) == :lt do
              [[message: "must be more than or equal to %{min}", min: min] | errors]
            else
              errors
            end

          {:less_than, less_than}, errors ->
            if Decimal.compare(value, less_than) == :lt do
              errors
            else
              [[message: "must be less than %{less_than}", less_than: less_than] | errors]
            end

          {:greater_than, greater_than}, errors ->
            if Decimal.compare(value, greater_than) == :gt do
              errors
            else
              [
                [message: "must be more than %{greater_than}", greater_than: greater_than]
                | errors
              ]
            end

          {:scale, scale}, errors ->
            if Decimal.scale(value) > scale do
              [
                [message: "must have no more than %{scale} decimal places", scale: scale]
                | errors
              ]
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
    def coerce(value, _) do
      cast_input(value, [])
    end

    @impl true
    def cast_input(nil, _constraints), do: {:ok, nil}

    def cast_input(value, _constraints) when is_binary(value) do
      case Decimal.parse(value) do
        {decimal, ""} ->
          {:ok, decimal}

        _ ->
          :error
      end
    end

    @impl true
    def cast_input(value, constraints) do
      case Ch.cast(value, ch_type(constraints)) do
        {:ok, decimal} ->
          {:ok, decimal}

        error ->
          error
      end
    end

    @impl true

    def cast_stored(value, _) when is_binary(value) do
      case Decimal.parse(value) do
        {decimal, ""} ->
          {:ok, decimal}

        _ ->
          :error
      end
    end

    @impl true
    def cast_stored(nil, _), do: {:ok, nil}

    def cast_stored(value, constraints) do
      Ch.load(value, nil, ch_type(constraints))
    end

    @impl true
    @spec dump_to_native(any, any) :: :error | {:ok, any}
    def dump_to_native(nil, _), do: {:ok, nil}

    def dump_to_native(value, constraints) do
      Ch.dump(value, nil, ch_type(constraints))
    end

    @doc false
    def new(%Decimal{} = v), do: v
    def new(v), do: Decimal.new(v)

    @impl true
    def equal?(nil, nil), do: true
    def equal?(nil, _right), do: false
    def equal?(_left, nil), do: false
    def equal?(left, right), do: Decimal.eq?(left, right)
  end
end
