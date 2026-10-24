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

  A `MyApp.Visitor` column is then ``JSON(`id` String)``; see
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
  The storage type of `type`, a module, stored as JSON with a typed path for
  each field whose type is a ClickHouse one, `Nullable` where the field allows
  nil, since ClickHouse reads a missing or null path as its type's default.

  Fields are those `type` declares through `Ash.Type.Map`, `Ash.Type.Struct` or
  `Ash.Type.Keyword`, so an `Ash.TypedStruct`'s too, nested or not, and those of
  a union's members, under `value` with `:type_and_value` storage. Other fields
  stay dynamic, as does a field that could not keep its nil: one whose type
  cannot be `Nullable`, and a nested map or union that allows nil, whose typed
  paths would read back as an object of defaults. A union with a member that is
  not a map stays dynamic whole, as that member's value would read back beside
  the typed paths under a duplicate key.
  Every row reads back every typed path, so union members must agree on a path
  they share, or the type raises. A type nested in itself, directly or through
  others, leaves its inner occurrence dynamic, as does an array of maps.

  `ch` has no term for typed JSON, so the storage type is the ClickHouse type as
  a string: ch writes it into an insert's header as it is, which ClickHouse
  requires to match the column, and reads the values as plain `JSON`. It is
  worked out once per type, as Ecto asks for it with every value it loads.
  """
  def storage_type_of(type) do
    key = {__MODULE__, type}

    with nil <- :persistent_term.get(key, nil) do
      storage_type =
        type
        |> typed_paths([], [], false, [])
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.flat_map(fn {path, column_types} ->
          case Enum.uniq(column_types) do
            [nil] ->
              []

            [column_type] ->
              ["`#{path}` #{column_type}"]

            column_types ->
              raise ArgumentError,
                    "#{inspect(type)} gives the JSON path #{path} different types: " <>
                      Enum.map_join(column_types, ", ", &(&1 || "dynamic"))
          end
        end)
        |> Enum.sort()
        |> case do
          [] -> {:parameterized, {Ch, :json}}
          paths -> {:parameterized, {Ch, "JSON(#{Enum.join(paths, ", ")})"}}
        end

      :persistent_term.put(key, storage_type)
      storage_type
    end
  end

  defp typed_paths({:array, _item_type}, _constraints, _path, false, _within), do: []

  defp typed_paths({:array, item_type} = type, constraints, path, true, _within) do
    case !constraints[:nullable?] and Ash.Type.NewType.subtype_of(item_type) not in @json_types and
           Ash.Type.storage_type(type, constraints) do
      {:array, {:parameterized, {Ch, ch_type}}}
      when not is_binary(ch_type) and ch_type not in @json_storage ->
        [{Enum.join(path, "."), MigrationGenerator.column_type(type, constraints)}]

      _storage_type ->
        [{Enum.join(path, "."), nil}]
    end
  end

  defp typed_paths(type, constraints, path, field?, within) do
    cond do
      type in within ->
        []

      Ash.Type.NewType.new_type?(type) ->
        typed_paths(
          type.subtype_of(),
          Keyword.merge(type.subtype_constraints(), constraints),
          path,
          field?,
          [type | within]
        )

      type in @json_types and constraints[:nullable?] ->
        []

      type == Ash.Type.Union ->
        member_path =
          if Keyword.get(constraints, :storage, :type_and_value) == :type_and_value,
            do: path ++ ["value"],
            else: path

        members = Enum.map(constraints[:types], fn {_name, config} -> config end)

        if Enum.all?(
             members,
             &(Ash.Type.NewType.subtype_of(Ash.Type.get_type(&1[:type])) in @json_types)
           ) do
          Enum.flat_map(members, fn config ->
            typed_paths(
              Ash.Type.get_type(config[:type]),
              config[:constraints] || [],
              member_path,
              false,
              within
            )
          end)
        else
          []
        end

      type in @json_types ->
        Enum.flat_map(constraints[:fields] || [], fn {name, config} ->
          constraints =
            if Keyword.get(config, :allow_nil?, true),
              do: Keyword.put(config[:constraints] || [], :nullable?, true),
              else: config[:constraints] || []

          typed_paths(
            Ash.Type.get_type(config[:type]),
            constraints,
            path ++ [to_string(name)],
            true,
            within
          )
        end)

      not field? ->
        []

      !constraints[:nullable?] or Keyword.has_key?(type.constraints(), :nullable?) ->
        case type.storage_type(constraints) do
          {:parameterized, {Ch, ch_type}} when ch_type not in @json_storage ->
            [{Enum.join(path, "."), MigrationGenerator.column_type(type, constraints)}]

          _storage_type ->
            [{Enum.join(path, "."), nil}]
        end

      true ->
        [{Enum.join(path, "."), nil}]
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
