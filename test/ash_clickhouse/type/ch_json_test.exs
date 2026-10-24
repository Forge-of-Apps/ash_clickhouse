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
            payloads: [type: {:array, ChJSON}, allow_nil?: false],
            nullable_payloads: [
              type: {:array, ChJSON},
              allow_nil?: false,
              constraints: [items: [nullable?: true]]
            ],
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

    defmodule Expr do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            literal: [
              type: :map,
              constraints: [fields: [n: [type: ChUint32, allow_nil?: false]]]
            ],
            binary: [type: AshClickhouse.Type.ChJsonTest.Binary, init?: false]
          ]
        ]
    end

    defmodule Binary do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            op: [type: ChString, allow_nil?: false],
            left: [type: Expr, allow_nil?: false, init?: false],
            right: [type: Expr, allow_nil?: false, init?: false]
          ]
        ]
    end

    defmodule Tree do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            name: [type: ChString, allow_nil?: false],
            children: [
              type: {:array, AshClickhouse.Type.ChJsonTest.Tree},
              allow_nil?: false,
              init?: false
            ]
          ]
        ]
    end

    defmodule Mixed do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            link: [type: :map, constraints: [fields: [url: [type: ChString, allow_nil?: false]]]],
            count: [type: ChUint32]
          ]
        ]
    end

    defmodule Quoted do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            "we`ird": [type: ChString, allow_nil?: false],
            "back\\slash": [type: ChString, allow_nil?: false]
          ]
        ]
    end

    defmodule Names do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            plan_id: [type: ChString, allow_nil?: false],
            plan: [type: ChString, allow_nil?: false],
            from: [type: ChString, allow_nil?: false],
            select: [type: ChString, allow_nil?: false],
            Null: [type: ChString, allow_nil?: false],
            id1: [type: ChString, allow_nil?: false],
            "1st": [type: ChString, allow_nil?: false],
            "a-b": [type: ChString, allow_nil?: false]
          ]
        ]
    end

    defmodule Shared do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            tron: [
              type: :map,
              constraints: [fields: [wallet: [type: ChString, allow_nil?: false]]]
            ],
            ethereum: [
              type: :map,
              constraints: [fields: [wallet: [type: ChString, allow_nil?: false]]]
            ]
          ]
        ]
    end

    defmodule Address do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [fields: [street: [type: ChString, allow_nil?: false]]]
    end

    defmodule Twins do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            billing: [type: AshClickhouse.Type.ChJsonTest.Address],
            shipping: [type: AshClickhouse.Type.ChJsonTest.Address]
          ]
        ]
    end

    defmodule Handle do
      use Ash.Type.NewType, subtype_of: AshClickhouse.Test.Resource.Types.Visitor.User
    end

    defmodule Nested do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            origin: [type: Origin, allow_nil?: false],
            handle: [type: Handle, allow_nil?: false],
            opts: [
              type: :keyword,
              allow_nil?: false,
              constraints: [fields: [mode: [type: :ch_string, allow_nil?: false]]]
            ]
          ]
        ]
    end

    defmodule Shapes do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [
          fields: [
            point: [type: AshClickhouse.Type.ChPoint],
            required_point: [type: AshClickhouse.Type.ChPoint, allow_nil?: false],
            counts: [
              type: AshClickhouse.Type.ChMap,
              constraints: [key_type: :ch_string, value_type: :ch_uint32]
            ],
            required_counts: [
              type: AshClickhouse.Type.ChMap,
              allow_nil?: false,
              constraints: [key_type: :ch_string, value_type: :ch_uint32]
            ],
            label: [type: ChString, constraints: [low_cardinality?: true]],
            meta: [type: ChJSON, allow_nil?: false]
          ]
        ]
    end

    defmodule NilMapClash do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            a: [
              type: :map,
              constraints: [
                fields: [
                  x: [
                    type: :map,
                    constraints: [fields: [id: [type: ChString, allow_nil?: false]]]
                  ]
                ]
              ]
            ],
            b: [type: :map, constraints: [fields: [x: [type: ChString, allow_nil?: false]]]]
          ]
        ]
    end

    defmodule ScalarMapClash do
      use Ash.Type.NewType,
        subtype_of: :union,
        constraints: [
          types: [
            a: [type: :map, constraints: [fields: [x: [type: ChString, allow_nil?: false]]]],
            b: [
              type: :map,
              constraints: [
                fields: [
                  x: [
                    type: :map,
                    allow_nil?: false,
                    constraints: [fields: [id: [type: ChString, allow_nil?: false]]]
                  ]
                ]
              ]
            ]
          ]
        ]
    end

    defmodule Dotted do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [fields: ["user.id": [type: ChString, allow_nil?: false]]]
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

    test "types a union's tag, and its map members under value" do
      assert {:parameterized,
              {Ch, "JSON(type LowCardinality(String), `value.code` String, `value.url` String)"}} =
               Ash.Type.storage_type(Origin, [])
    end

    test "types only the tag of a union with a member that is not a map" do
      assert {:parameterized, {Ch, "JSON(type LowCardinality(String))"}} =
               ChJSON.storage_type_of(Mixed)
    end

    test "types a :map_with_tag union's members at the top, with no tag of its own" do
      assert {:parameterized, {Ch, "JSON(url String)"}} = ChJSON.storage_type_of(Tagged)
    end

    test "leaves dynamic the fields that could not keep a nil, nested maps included" do
      assert {:parameterized,
              {Ch,
               "JSON(required_level Enum8('enum8_min' = -128, 'enum8_zero' = 0, 'enum8_max' = 127), required_tags Array(String))"}} =
               ChJSON.storage_type_of(Fields)
    end

    test "leaves a type nested in itself dynamic where it recurs" do
      assert {:parameterized,
              {Ch, "JSON(type LowCardinality(String), `value.n` UInt32, `value.op` String)"}} =
               ChJSON.storage_type_of(Expr)

      assert {:parameterized, {Ch, "JSON(name String)"}} = ChJSON.storage_type_of(Tree)
    end

    test "escapes backticks and backslashes in a path" do
      assert {:parameterized, {Ch, ~S"JSON(`back\\slash` String, `we\`ird` String)"}} =
               ChJSON.storage_type_of(Quoted)
    end

    test "spells path names and orders paths as ClickHouse does" do
      assert {:parameterized,
              {Ch,
               "JSON(`1st` String, `Null` String, `a-b` String, from String, id1 String, plan String, plan_id String, `select` String)"}} =
               ChJSON.storage_type_of(Names)
    end

    test "types a path once that union members share" do
      assert {:parameterized, {Ch, "JSON(type LowCardinality(String), `value.wallet` String)"}} =
               ChJSON.storage_type_of(Shared)
    end

    test "types a union whose members share one type" do
      assert {:parameterized, {Ch, "JSON(type LowCardinality(String), `value.street` String)"}} =
               ChJSON.storage_type_of(Twins)
    end

    test "types nested unions, their tags included, new types over new types and keyword fields" do
      assert {:parameterized,
              {Ch,
               "JSON(`handle.id` String, `handle.plan` Nullable(String), `handle.visits` UInt32, `opts.mode` String, `origin.type` LowCardinality(String), `origin.value.code` String, `origin.value.url` String)"}} =
               ChJSON.storage_type_of(Nested)
    end

    test "leaves dynamic a field whose type ClickHouse cannot make Nullable" do
      assert {:parameterized,
              {Ch,
               "JSON(label LowCardinality(Nullable(String)), required_counts Map(String, UInt32), required_point Point)"}} =
               ChJSON.storage_type_of(Shapes)
    end

    test "renders every type as ClickHouse names it, which an insert's header must match" do
      for type <- [
            Visitor,
            Origin,
            Mixed,
            Fields,
            Tagged,
            Expr,
            Tree,
            Quoted,
            Names,
            Shared,
            Twins,
            Nested,
            Shapes
          ] do
        {:parameterized, {Ch, column_type}} = ChJSON.storage_type_of(type)

        assert %{rows: [[^column_type]]} =
                 AshClickhouse.TestRepo.query!("SELECT toTypeName(CAST('{}', {$0:String}))", [
                   column_type
                 ])
      end
    end

    test "is worked out once per type" do
      storage_type = ChJSON.storage_type_of(Visitor)

      assert :persistent_term.get({ChJSON, Visitor}) == storage_type
    end

    test "refuses a union member leaving dynamic a path another types" do
      assert_raise ArgumentError, ~r/path value.x different types: dynamic, String/, fn ->
        ChJSON.storage_type_of(NilMapClash)
      end
    end

    test "refuses a path with a value of its own and paths inside it" do
      assert_raise ArgumentError,
                   ~r/path value.x a value of its own and the path value.x.id inside it/,
                   fn -> ChJSON.storage_type_of(ScalarMapClash) end
    end

    test "refuses a field named with a dot, which ClickHouse reads back as nested objects" do
      assert_raise ArgumentError, ~r/the field :"user.id" at "" would not read back/, fn ->
        ChJSON.storage_type_of(Dotted)
      end
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
