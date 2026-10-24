defmodule AshClickhouse.Type.ChJSON do
  use Ash.Type
  require AshClickhouse.Type.Helper

  alias AshClickhouse.MigrationGenerator

  @json_types [Ash.Type.Union, Ash.Type.Map, Ash.Type.Struct, Ash.Type.Keyword]
  @json_storage [:json, {:nullable, :json}]

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

  ### Typed paths

  A type that stores itself as JSON, such as a union or an `Ash.TypedStruct`,
  can have its fields of ClickHouse types stored as typed paths, which a
  sorting key may name, unlike an untyped path, whose values are `Dynamic`:

      defmodule MyApp.Visitor do
        use Ash.TypedStruct

        typed_struct do
          field :id, AshClickhouse.Type.ChString, allow_nil?: false
          field :referrer, :string
        end

        @impl true
        def storage_type(_constraints), do: AshClickhouse.Type.ChJSON.storage_type_of(__MODULE__)
      end

  A `MyApp.Visitor` column is then `JSON(id String)`; see
  `storage_type_of/1`.

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

  @doc """
  The storage type of `type`, a module that stores itself as JSON, with a typed
  path for each of its fields of a ClickHouse type.

    * Fields are those of `Ash.Type.Map`, `Ash.Type.Struct` and `Ash.Type.Keyword`,
      an `Ash.TypedStruct`'s among them, nested or not, and of a union's members,
      under `value` with `:type_and_value` storage.
    * A field allowing nil is `Nullable`, since ClickHouse reads a missing or null
      path as its type's default.
    * A field stays dynamic where ClickHouse could not hold it typed: a type not
      of ClickHouse, JSON itself, a nil its type cannot be `Nullable` for, an
      array of objects, a nested object allowing nil, a type recurring inside
      itself, and every field of a union with a member that is not an object.
    * Every row reads back every typed path, so the type raises where union
      members type one path differently, or a path has a value of its own and
      paths inside it. A field named with a dot raises too: ClickHouse reads such
      a key back as nested objects, typed or not.

  `ch` has no term for typed JSON, so the result is the ClickHouse type as a
  string, spelt as ClickHouse spells it: ch writes it into an insert's header as
  it is, and ClickHouse compares that header with the column's type as a string.
  It is cached per type, as Ecto asks for it with every value it loads.
  """
  def storage_type_of(type) do
    key = {__MODULE__, type}

    with nil <- :persistent_term.get(key, nil) do
      typed =
        for {path, column_type} <- type |> object_paths([], [], []) |> agreed_paths!(type),
            column_type != :dynamic,
            do: "#{identifier(path)} #{column_type}"

      storage_type =
        case typed do
          [] -> {:parameterized, {Ch, :json}}
          typed -> {:parameterized, {Ch, "JSON(#{Enum.join(typed, ", ")})"}}
        end

      :persistent_term.put(key, storage_type)
      storage_type
    end
  end

  defp agreed_paths!(paths, type) do
    paths =
      paths
      |> Enum.group_by(fn {path, _column_type} -> Enum.join(path, ".") end, &elem(&1, 1))
      |> Enum.map(fn {path, column_types} ->
        case Enum.uniq(column_types) do
          [column_type] ->
            {path, column_type}

          column_types ->
            raise ArgumentError,
                  "#{inspect(type)} gives the JSON path #{path} different types: " <>
                    Enum.join(column_types, ", ")
        end
      end)
      |> Enum.sort()

    for {path, _column_type} <- paths,
        {inner, _column_type} <- paths,
        String.starts_with?(inner, path <> ".") do
      raise ArgumentError,
            "#{inspect(type)} gives the JSON path #{path} a value of its own and the path #{inner} inside it"
    end

    paths
  end

  defp object_paths(type, constraints, path, within) do
    cond do
      type in within ->
        [{path, :dynamic}]

      Ash.Type.NewType.new_type?(type) ->
        object_paths(
          type.subtype_of(),
          Keyword.merge(type.subtype_constraints(), constraints),
          path,
          [type | within]
        )

      type == Ash.Type.Union ->
        members =
          for {_name, config} <- constraints[:types] do
            member = Ash.Type.get_type(config[:type])
            {member, Ash.Type.NewType.subtype_of(member), config[:constraints] || []}
          end

        value_path =
          if Keyword.get(constraints, :storage, :type_and_value) == :type_and_value,
            do: path ++ ["value"],
            else: path

        if Enum.all?(members, fn {_member, base, _constraints} -> base in @json_types end) do
          Enum.flat_map(members, fn {member, _base, constraints} ->
            object_paths(member, constraints, value_path, within)
          end)
        else
          [{path, :dynamic}]
        end

      true ->
        Enum.flat_map(constraints[:fields] || [], &field_paths(&1, path, within))
    end
  end

  defp field_paths({name, config}, path, within) do
    if String.contains?(to_string(name), ".") do
      raise ArgumentError,
            "the field #{inspect(name)} at #{inspect(Enum.join(path, "."))} would not read back: " <>
              "ClickHouse JSON reads a key with dots as nested objects"
    end

    type = Ash.Type.get_type(config[:type])
    constraints = config[:constraints] || []
    path = path ++ [to_string(name)]
    nullable? = Keyword.get(config, :allow_nil?, true)

    case Ash.Type.NewType.subtype_of(type) do
      base when base in @json_types and nullable? -> [{path, :dynamic}]
      base when base in @json_types -> object_paths(type, constraints, path, within)
      {:array, _item_type} when nullable? -> [{path, :dynamic}]
      {:array, item_type} when item_type in @json_types -> [{path, :dynamic}]
      _base -> [{path, leaf_type(type, constraints, nullable?)}]
    end
  end

  defp leaf_type(type, constraints, nullable?) do
    constraints = if nullable?, do: Keyword.put(constraints, :nullable?, true), else: constraints

    case Ash.Type.storage_type(type, constraints) do
      {:array, {:parameterized, {Ch, ch_type}}} when ch_type not in @json_storage ->
        MigrationGenerator.column_type(type, constraints)

      {:parameterized, {Ch, ch_type}} when ch_type not in @json_storage ->
        if constraints[:nullable?] && !nullable_storage?(ch_type),
          do: :dynamic,
          else: MigrationGenerator.column_type(type, constraints)

      _storage_type ->
        :dynamic
    end
  end

  defp nullable_storage?({:low_cardinality, {:nullable, _type}}), do: true

  defp nullable_storage?({:nullable, {kind, _type}}) when kind in [:array, :tuple, :variant],
    do: false

  defp nullable_storage?({:nullable, {:map, _key_type, _value_type}}), do: false

  defp nullable_storage?({:nullable, type}),
    do: type not in [:point, :ring, :polygon, :multipolygon, :dynamic]

  defp nullable_storage?(_type), do: false

  defp identifier(path) do
    if path =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ and
         String.downcase(path) not in ~w(null select all distinct table) do
      path
    else
      "`" <> String.replace(path, ["\\", "`"], &("\\" <> &1)) <> "`"
    end
  end

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
