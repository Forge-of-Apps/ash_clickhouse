defmodule AshClickhouse.Type.ChJSON do
  use Ash.Type
  require AshClickhouse.Type.Helper

  alias AshClickhouse.MigrationGenerator

  @constraints [
    nullable?: [
      type: :boolean,
      default: false,
      doc: "Whether the JSON can be null: Nullable(JSON)"
    ],
    paths: [
      type: {:map, :string, :any},
      doc: """
      Paths stored with a fixed type, as `%{"path.to.field" => type}`, where a
      type is an `AshClickhouse.Type.Ch*` module or `{module, constraints}`.
      """
    ]
  ]

  @moduledoc """
  Represents a JSON, with configurable nullable.

  Registered as `:ch_json` where short type names are configured (see
  `AshClickhouse`); an attribute can always name this module instead.

  ### Typed paths

  `paths` gives paths a type of their own, created as
  ``JSON(`user.id` String)``. A sorting key can name a typed path but not
  an untyped one, whose values are `Dynamic`:

      attribute :visitor, AshClickhouse.Type.ChJSON,
        constraints: [paths: %{"user.id" => AshClickhouse.Type.ChString}]

  `ch` has no type term for typed JSON, so with paths the storage type holds
  the ClickHouse type as a string. `ch` writes that string into an insert's
  header as it is, which ClickHouse requires to match the column exactly, and
  decodes it as plain `JSON` for the values, which are cast, written and read
  back as they are without paths. A type stored as JSON without being this
  one, such as a union, gets typed paths by returning this `storage_type/1`.

  ### Constraints

  #{Spark.Options.docs(@constraints)}
  """

  AshClickhouse.Type.Helper.graphql_type(__MODULE__, :ch_json, :json)

  @impl true
  def constraints, do: @constraints

  @impl true
  def storage_type(constraints) do
    case constraints |> Keyword.get(:paths, %{}) |> Enum.sort() do
      [] ->
        {:parameterized, {Ch, ch_type(constraints)}}

      paths ->
        typed =
          Enum.map_join(paths, ", ", fn
            {path, {type, constraints}} when is_list(constraints) ->
              "`#{path}` #{MigrationGenerator.column_type(type, constraints)}"

            {path, type} ->
              "`#{path}` #{MigrationGenerator.column_type(type, [])}"
          end)

        json = "JSON(#{typed})"
        {:parameterized, {Ch, if(constraints[:nullable?], do: "Nullable(#{json})", else: json)}}
    end
  end

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
