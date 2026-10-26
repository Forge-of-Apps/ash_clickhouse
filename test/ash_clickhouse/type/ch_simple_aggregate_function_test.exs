defmodule AshClickhouse.Type.ChSimpleAggregateFunctionTest do
  use ExUnit.Case, async: true

  alias AshClickhouse.Type.ChSimpleAggregateFunction

  import AshClickhouse.Test.Helper, only: [encode_ch_type: 1]

  describe "storage_type/1" do
    test "aggregates a type without constraints" do
      constraints = [function: "sum", type: :ch_int64]

      assert {:ok, ^constraints} = Ash.Type.init(ChSimpleAggregateFunction, constraints)

      assert encode_ch_type(Ash.Type.storage_type(ChSimpleAggregateFunction, constraints)) ==
               "SimpleAggregateFunction(sum, Int64)"
    end

    test "aggregates a type with its constraints, given as a one-entry keyword list" do
      constraints = [function: "min", type: [ch_datetime: [timezone: "UTC"]]]

      assert {:ok, ^constraints} = Ash.Type.init(ChSimpleAggregateFunction, constraints)

      assert encode_ch_type(Ash.Type.storage_type(ChSimpleAggregateFunction, constraints)) ==
               "SimpleAggregateFunction(min, DateTime('UTC'))"
    end

    test "aggregates a type named by its module" do
      constraints = [
        function: "max",
        type: [{AshClickhouse.Type.ChString, [low_cardinality?: true]}]
      ]

      assert {:ok, ^constraints} = Ash.Type.init(ChSimpleAggregateFunction, constraints)

      assert encode_ch_type(Ash.Type.storage_type(ChSimpleAggregateFunction, constraints)) ==
               "SimpleAggregateFunction(max, LowCardinality(String))"
    end
  end

  describe "ch_type/1 with constraints no schema checked" do
    test "aggregates a type given with its constraints as a tuple" do
      constraints = [function: "min", type: {AshClickhouse.Type.ChDateTime, [timezone: "UTC"]}]

      assert encode_ch_type(ChSimpleAggregateFunction.storage_type(constraints)) ==
               "SimpleAggregateFunction(min, DateTime('UTC'))"
    end

    test "aggregates a type given as a tuple inside a map, which hands its value's constraints on unchecked" do
      constraints = [
        key_type: :ch_string,
        value_type: [
          ch_simple_aggregate_function: [
            function: "min",
            type: {AshClickhouse.Type.ChDateTime, [timezone: "UTC"]}
          ]
        ]
      ]

      assert {:ok, _constraints} = Ash.Type.init(AshClickhouse.Type.ChMap, constraints)

      assert encode_ch_type(Ash.Type.storage_type(AshClickhouse.Type.ChMap, constraints)) ==
               "Map(String, SimpleAggregateFunction(min, DateTime('UTC')))"
    end
  end

  describe "cast_input/2" do
    test "casts as the aggregated type" do
      constraints = [function: "min", type: [ch_datetime: [timezone: "UTC"]]]

      assert {:ok, ~U[2026-01-02 03:04:05Z]} =
               Ash.Type.cast_input(ChSimpleAggregateFunction, "2026-01-02 03:04:05", constraints)

      assert {:error, _} =
               Ash.Type.cast_input(ChSimpleAggregateFunction, "not a time", constraints)
    end
  end
end
