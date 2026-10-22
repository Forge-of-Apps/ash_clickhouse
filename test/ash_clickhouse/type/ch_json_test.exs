defmodule AshClickhouse.Type.ChJsonTest do
  use ExUnit.Case, async: true

  alias AshClickhouse.Test.Resource.Types.Origin
  alias AshClickhouse.Test.Resource.Types.TestEnum8
  alias AshClickhouse.Test.Resource.Types.Visitor
  alias AshClickhouse.Type.ChJSON
  alias AshClickhouse.Type.ChString
  alias AshClickhouse.Type.ChUint32

  import AshClickhouse.Test.Helper, only: [encode_ch_type: 1]

  describe "storage_types" do
    test "returns correct ClickHouse type without constraints" do
      assert {:parameterized, {Ch, :json}} = type = Ash.Type.storage_type(ChJSON, [])
      assert encode_ch_type(type) == "JSON"
    end

    test "returns correct ClickHouse type with nullable constraint" do
      assert {:parameterized, {Ch, {:nullable, :json}}} =
               type = Ash.Type.storage_type(ChJSON, nullable?: true)

      assert encode_ch_type(type) == "Nullable(JSON)"
    end

    test "returns correct ClickHouse type for array version" do
      assert {:array, {:parameterized, {Ch, :json}} = subtype} =
               Ash.Type.storage_type({:array, ChJSON}, [])

      assert encode_ch_type({:array, subtype}) == "Array(JSON)"
    end

    test "returns correct ClickHouse type for array version with nullable constraint" do
      assert {:array, {:parameterized, {Ch, {:nullable, :json}}} = subtype} =
               Ash.Type.storage_type({:array, ChJSON}, items: [nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(JSON))"
    end
  end

  describe "storage_type_of/1" do
    defmodule Fields do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            note: [type: :string],
            level: [type: TestEnum8],
            required_level: [type: TestEnum8, allow_nil?: false],
            tags: [type: {:array, :ch_string}],
            required_tags: [type: {:array, :ch_string}, allow_nil?: false],
            owner: [
              type: :map,
              constraints: [fields: [id: [type: ChString, allow_nil?: false]]]
            ]
          ]
        ]
    end

    defmodule Untyped do
      use Ash.Type.NewType, subtype_of: :map, constraints: [fields: [note: [type: :string]]]
    end

    defmodule Tagged do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          storage: :map_with_tag,
          types: [
            link: [
              type: :map,
              tag: :kind,
              tag_value: "link",
              constraints: [
                fields: [
                  kind: [type: :string],
                  url: [type: ChString, allow_nil?: false]
                ]
              ]
            ]
          ]
        ]
    end

    defmodule HalfTyped do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            a: [type: :map, constraints: [fields: [x: [type: ChString, allow_nil?: false]]]],
            b: [type: :map, constraints: [fields: [x: [type: :string, allow_nil?: false]]]]
          ]
        ]
    end

    defmodule Clashing do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            a: [type: :map, constraints: [fields: [x: [type: ChString, allow_nil?: false]]]],
            b: [type: :map, constraints: [fields: [x: [type: ChUint32, allow_nil?: false]]]]
          ]
        ]
    end

    test "types a typed struct's fields of ClickHouse types, nested ones included" do
      assert {:parameterized,
              {Ch, "JSON(`user.id` String, `user.plan` Nullable(String), `user.visits` UInt32)"}} =
               ChJSON.storage_type_of(Visitor)
    end

    test "types a union's map members under value, leaving its other members dynamic" do
      assert {:parameterized, {Ch, "JSON(`value.url` String)"}} =
               Ash.Type.storage_type(Origin, [])
    end

    test "types a :map_with_tag union's members at the top" do
      assert {:parameterized, {Ch, "JSON(`url` String)"}} = ChJSON.storage_type_of(Tagged)
    end

    test "leaves dynamic the fields that could not keep a nil, nested maps included" do
      assert {:parameterized,
              {Ch,
               "JSON(`required_level` Enum8('enum8_min' = -128, 'enum8_zero' = 0, 'enum8_max' = 127), `required_tags` Array(String))"}} =
               ChJSON.storage_type_of(Fields)
    end

    test "is plain JSON when no field has a ClickHouse type" do
      assert {:parameterized, {Ch, :json}} = ChJSON.storage_type_of(Untyped)
    end

    test "refuses members typing one path differently" do
      assert_raise ArgumentError, ~r/path value.x different types: String, UInt32/, fn ->
        ChJSON.storage_type_of(Clashing)
      end
    end

    test "refuses a path one member types and another leaves dynamic" do
      assert_raise ArgumentError, ~r/path value.x different types: String, dynamic/, fn ->
        ChJSON.storage_type_of(HalfTyped)
      end
    end
  end

  describe "cast_input/2" do
    test "cast atom key map to internal representation" do
      assert {:ok, %{"name" => "John", "age" => 30}} =
               Ash.Type.cast_input(ChJSON, %{name: "John", age: 30}, [])
    end

    test "cast string key map to internal representation" do
      assert {:ok, %{"name" => "John", "age" => 30}} =
               Ash.Type.cast_input(ChJSON, %{"name" => "John", "age" => 30}, [])
    end

    test "cast string json to internal representation" do
      assert {:ok, %{"name" => "John", "age" => 30}} =
               Ash.Type.cast_input(ChJSON, ~s({"name": "John", "age": 30}), [])
    end

    test "returns error for invalid JSON string" do
      assert {:error, "is invalid"} = Ash.Type.cast_input(ChJSON, "invalid", [])
    end

    test "casts valid JSON string to internal representation for array version" do
      assert {:ok,
              [
                %{"age" => 30, "name" => "John"},
                %{"age" => 30, "name" => "John"},
                %{"name" => "John", "age" => 30}
              ]} =
               Ash.Type.cast_input(
                 {:array, ChJSON},
                 [
                   %{name: "John", age: 30},
                   %{"name" => "John", "age" => 30},
                   ~s({"name": "John", "age": 30})
                 ],
                 []
               )
    end
  end

  describe "matches_type?/2" do
    test "returns true for valid JSON" do
      assert Ash.Type.matches_type?(ChJSON, ~s({"name": "John", "age": 30}), [])
    end

    test "returns false for invalid JSON" do
      refute Ash.Type.matches_type?(ChJSON, "invalid", [])
      refute Ash.Type.matches_type?(ChJSON, nil, [])
    end
  end

  describe "cast_stored/2" do
    test "casts stored JSON to internal representation" do
      assert {:ok, %{"name" => "John", "age" => 30}} =
               Ash.Type.cast_stored(ChJSON, ~s({"name": "John", "age": 30}), [])
    end
  end
end
