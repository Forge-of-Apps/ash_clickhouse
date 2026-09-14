defmodule AshClickhouse.Type.ChFixedString do
  @constraints [
    length: [
      type: :non_neg_integer,
      required: true,
      doc: "The length of the fixed string: FixedString(length)"
    ],
    match: [
      type: :regex_as_mfa,
      doc: "Enforces that the string matches a passed in regex"
    ],
    trim?: [
      type: :boolean,
      doc: "Trims the value.",
      default: true
    ],
    allow_empty?: [
      type: :boolean,
      doc: "If false, the value is set to `nil` if it's empty.",
      default: false
    ],
    low_cardinality?: [
      type: :boolean,
      doc: "If true, the value is stored as a LowCardinality(FixedString(length))",
      default: false
    ],
    nullable?: [
      type: :boolean,
      doc:
        "If true, the value is stored as a Nullable(FixedString(length)) or Nullable(LowCardinality(FixedString(length))) if low_cardinality? is true",
      default: false
    ]
  ]

  @moduledoc """
  Stores a string in the database.

  Registered as `:ch_fixed_string` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  By default, values are trimmed and empty values are set to `nil`.
  You can use the `allow_empty?` and `trim?` constraints to change these behaviors.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """
  use Ash.Type

  require Ash.Expr
  require AshClickhouse.Type.Helper

  AshClickhouse.Type.Helper.graphql_type(__MODULE__, :ch_fixed_string, :string)

  @impl true
  def storage_type(constraints) do
    {:parameterized, {Ch, ch_type(constraints)}}
  end

  def ch_type(constraints) do
    if is_nil(constraints[:length]) do
      raise "`length` is required for `:ch_fixed_string`"
    end

    Ch.Types.fixed_string(constraints[:length])
    |> maybe_nullable(constraints[:nullable?])
    |> maybe_low_cardinality(constraints[:low_cardinality?])
  end

  defp maybe_low_cardinality(type, true), do: Ch.Types.low_cardinality(type)
  defp maybe_low_cardinality(type, _), do: type

  defp maybe_nullable(type, true), do: Ch.Types.nullable(type)
  defp maybe_nullable(type, _), do: type

  @impl true
  def matches_type?(v, _) do
    is_binary(v)
  end

  @impl true
  def cast_atomic(expr, constraints) when is_binary(expr) do
    with {:ok, value} <- cast_input(expr, constraints) do
      {:atomic, value}
    end
  end

  @impl true
  def cast_atomic(expr, constraints) do
    # We can't support `match` currently, as we don't have a multi-target regex
    if constraints[:match] do
      {:not_atomic, "cannot use the `match` string constraint atomically with an expression"}
    else
      expr =
        if constraints[:trim?] do
          Ash.Expr.expr(string_trim(^expr))
        else
          expr
        end

      expr =
        if constraints[:allow_empty?] do
          expr
        else
          Ash.Expr.expr(
            if ^expr == "" do
              nil
            else
              ^expr
            end
          )
        end

      {:atomic, expr}
    end
  end

  @impl true
  def apply_atomic_constraints(expr, constraints) do
    apply_constraints(expr, constraints)
  end

  @impl true
  def constraints, do: @constraints

  @impl true
  def generator(constraints) do
    base_generator =
      StreamData.string(
        :printable,
        Keyword.take(constraints, [:length])
      )

    cond do
      constraints[:trim?] && constraints[:length] ->
        StreamData.filter(base_generator, fn value ->
          value |> String.trim() |> String.length() |> Kernel.==(constraints[:length])
        end)

      constraints[:length] ->
        StreamData.filter(base_generator, fn value ->
          value |> String.length() |> Kernel.==(constraints[:length])
        end)

      true ->
        base_generator
    end
  end

  @impl true
  def apply_constraints(nil, _), do: :ok

  def apply_constraints(value, constraints) do
    {value, errors} =
      return_value(
        Keyword.get(constraints, :allow_empty?, false),
        Keyword.get(constraints, :trim?, true),
        value,
        constraints
      )

    case errors do
      [] -> {:ok, value}
      [error] -> {:error, error}
      errors -> {:error, errors}
    end
  end

  defp return_value(false, true, value, constraints) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {nil, []}
    else
      {trimmed, validate(trimmed, constraints)}
    end
  end

  defp return_value(false, false, value, constraints) do
    if String.trim(value) == "" do
      {nil, []}
    else
      {value, validate(value, constraints)}
    end
  end

  defp return_value(true, true, value, constraints) do
    trimmed = String.trim(value)
    {trimmed, validate(trimmed, constraints)}
  end

  defp return_value(true, false, value, constraints),
    do: {value, validate(value, constraints)}

  defp validate(value, constraints) do
    Enum.reduce(constraints, [], fn
      {:length, length}, errors ->
        if String.length(value) != length do
          [
            [message: "length must be equal to %{length}", length: length]
            | errors
          ]
        else
          errors
        end

      {:match, regex}, errors ->
        {m, f, a} = regex

        regex =
          apply(m, f, a)

        if Regex.match?(regex, value) do
          errors
        else
          [[message: "must match the pattern %{regex}", regex: inspect(regex)] | errors]
        end

      _, errors ->
        errors
    end)
  end

  @impl true
  def cast_input(%Ash.CiString{} = ci_string, constraints) do
    ci_string
    |> Ash.CiString.value()
    |> cast_input(constraints)
  end

  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(value, constraints) when is_atom(value) do
    cast_input(to_string(value), constraints)
  end

  def cast_input(value, constraints) do
    Ch.cast(value, ch_type(constraints))
  end

  @impl true
  def coerce(value, _constraints) do
    case cast_input(value, allow_empty?: true, trim?: false) do
      {:ok, value} ->
        {:ok, value}

      _ ->
        if String.Chars.impl_for(value) do
          {:ok, to_string(value)}
        else
          {:error, "could not be coerced"}
        end
    end
  end

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, constraints) do
    Ch.load(value, nil, ch_type(constraints))
  end

  @impl true

  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(value, constraints) do
    Ch.dump(value, nil, ch_type(constraints))
  end
end
