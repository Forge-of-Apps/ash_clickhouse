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

  describe "cast_input/2" do
    test "casts as the aggregated type" do
      constraints = [function: "min", type: [ch_datetime: [timezone: "UTC"]]]

      assert {:ok, ~U[2026-01-02 03:04:05Z]} =
               Ash.Type.cast_input(
                 ChSimpleAggregateFunction,
                 ~U[2026-01-02 03:04:05Z],
                 constraints
               )
    end
  end
end
