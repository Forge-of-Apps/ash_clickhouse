defmodule AshClickhouse.Type.ChDecimalTest do
  use ExUnit.Case, async: true
  alias AshClickhouse.Type.ChDecimal
  import AshClickhouse.Test.Helper, only: [encode_ch_type: 1]

  describe "storage_types" do
    test "returns correct ClickHouse type without constraints" do
      assert {:parameterized, {Ch, {:decimal, 10, 2}}} =
               type = ChDecimal.storage_type(precision: 10, scale: 2)

      assert encode_ch_type(type) == "Decimal(10, 2)"
    end

    test "returns correct ClickHouse type with precision and scale constraints" do
      assert {:parameterized, {Ch, {:decimal, 20, 5}}} =
               type = ChDecimal.storage_type(precision: 20, scale: 5)

      assert encode_ch_type(type) == "Decimal(20, 5)"
    end

    test "returns nullable ClickHouse type with nullable constraint" do
      assert {:parameterized, {Ch, {:nullable, {:decimal, 18, 4}}}} =
               type = ChDecimal.storage_type(precision: 18, scale: 4, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Decimal(18, 4))"
    end

    test "returns correct ClickHouse type without constraints for array version" do
      assert {:array, {:parameterized, {Ch, {:decimal, 10, 2}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal}, items: [precision: 10, scale: 2])

      assert encode_ch_type({:array, subtype}) == "Array(Decimal(10, 2))"
    end

    test "returns nullable ClickHouse type with nullable constraint for array version" do
      assert {:array, {:parameterized, {Ch, {:nullable, {:decimal, 18, 4}}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal},
                 items: [precision: 18, scale: 4, nullable?: true]
               )

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Decimal(18, 4)))"
    end
  end

  describe "matches_type?/2" do
    test "returns true for Decimal structs" do
      assert ChDecimal.matches_type?(Decimal.new("123.45"), [])
      assert ChDecimal.matches_type?(Decimal.new("0.001"), [])
    end

    test "returns false for non-Decimal values" do
      refute ChDecimal.matches_type?(nil, [])
      refute ChDecimal.matches_type?(123.45, [])
      refute ChDecimal.matches_type?("123.45", [])
      refute ChDecimal.matches_type?([], [])
    end

    test "returns true for arrays of Decimal structs" do
      assert Ash.Type.matches_type?(
               {:array, ChDecimal},
               [Decimal.new("123.45"), Decimal.new("0.001")],
               []
             )
    end

    test "returns false for non-Decimal arrays" do
      refute Ash.Type.matches_type?({:array, ChDecimal}, [123.45, 678.90], [])
      refute Ash.Type.matches_type?({:array, ChDecimal}, ["123.45", "678.90"], [])
      refute Ash.Type.matches_type?({:array, ChDecimal}, [[], {}], [])
    end
  end

  describe "generator" do
    test "generates Decimal structs within specified constraints" do
      constraints = [min: Decimal.new("10.00"), max: Decimal.new("20.00")]
      generated_decimals = Enum.take(ChDecimal.generator(constraints), 100) |> Enum.uniq()

      assert Enum.all?(generated_decimals, fn decimal ->
               Decimal.compare(decimal, constraints[:min]) != :lt and
                 Decimal.compare(decimal, constraints[:max]) != :gt
             end)
    end

    test "generates arrays of Decimal structs within specified constraints" do
      constraints = [
        precision: 10,
        scale: 2,
        min: Decimal.new("10.00"),
        max: Decimal.new("20.00")
      ]

      generated_arrays =
        Enum.take(Ash.Type.generator({:array, ChDecimal}, items: constraints), 100)

      assert Enum.all?(generated_arrays, fn arr ->
               is_list(arr) and
                 Enum.all?(arr, fn decimal ->
                   Decimal.compare(decimal, constraints[:min]) != :lt and
                     Decimal.compare(decimal, constraints[:max]) != :gt
                 end)
             end)
    end
  end

  describe "apply_constraints/2" do
    test "returns ok for valid Decimal within constraints" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      assert Ash.Type.apply_constraints(ChDecimal, Decimal.new("10.00"), constraints) ==
               {:ok, Decimal.new("10.00")}
    end

    test "returns error for Decimal below min constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]
      {:error, errors} = Ash.Type.apply_constraints(ChDecimal, Decimal.new("3.00"), constraints)

      assert errors == [
               [message: "must be more than or equal to %{min}", min: Decimal.new("5.00")]
             ]
    end

    test "returns error for Decimal above max constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]
      {:error, errors} = Ash.Type.apply_constraints(ChDecimal, Decimal.new("20.00"), constraints)

      assert errors == [
               [message: "must be less than or equal to %{max}", max: Decimal.new("15.00")]
             ]
    end

    test "returns ok for valid array of Decimals within constraints" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      assert Ash.Type.apply_constraints(
               {:array, ChDecimal},
               [Decimal.new("10.00"), Decimal.new("12.00")],
               items: constraints
             ) ==
               {:ok, [Decimal.new("10.00"), Decimal.new("12.00")]}
    end

    test "returns error for array with Decimal below min constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      {:error, errors} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal},
          [Decimal.new("10.00"), Decimal.new("3.00")],
          items: constraints
        )

      assert length(errors) == 1
      [error] = errors
      assert error[:message] =~ "must be more than or equal to %{min}"
    end

    test "returns error for array with Decimal above max constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      {:error, errors} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal},
          [Decimal.new("10.00"), Decimal.new("20.00")],
          items: constraints
        )

      assert length(errors) == 1
      [error] = errors
      assert error[:message] =~ "must be less than or equal to %{max}"
    end
  end

  describe "string casts beyond decimal128 precision" do
    test "parses up to ClickHouse's 76 digits" do
      digits76 = String.duplicate("9", 74) <> ".99"

      assert {:ok, %Decimal{}} =
               Ash.Type.cast_input(ChDecimal, digits76, precision: 76, scale: 2)

      assert {:ok, %Decimal{}} =
               Ash.Type.cast_stored(ChDecimal, digits76, precision: 76, scale: 2)

      assert %Decimal{} = ChDecimal.new(digits76)
    end
  end

  describe "cast_input/2" do
    test "casts valid Decimal correctly" do
      assert ChDecimal.cast_input(Decimal.new("123.45"), precision: 5, scale: 2) ==
               {:ok, Decimal.new("123.45")}

      assert ChDecimal.cast_input("678.90", precision: 5, scale: 2) ==
               {:ok, Decimal.new("678.90")}

      assert ChDecimal.cast_input(123.45, precision: 5, scale: 2) == {:ok, Decimal.new("123.45")}
      assert ChDecimal.cast_input(nil, precision: 5, scale: 2) == {:ok, nil}
    end

    test "returns error for invalid inputs" do
      assert ChDecimal.cast_input("invalid", []) == :error
    end

    test "casts valid array of Decimals correctly" do
      assert Ash.Type.cast_input(
               {:array, ChDecimal},
               [Decimal.new("123.45"), Decimal.new("678.90")],
               items: [precision: 5, scale: 2]
             ) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.90")]}

      assert Ash.Type.cast_input({:array, ChDecimal}, ["123.45", "678.90"],
               items: [precision: 5, scale: 2]
             ) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.90")]}

      assert Ash.Type.cast_input({:array, ChDecimal}, [123.45, 678.9],
               items: [precision: 5, scale: 2]
             ) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.9")]}

      assert Ash.Type.cast_input({:array, ChDecimal}, [nil, Decimal.new("123.45")],
               items: [precision: 5, scale: 2]
             ) ==
               {:ok, [nil, Decimal.new("123.45")]}
    end

    test "returns error for invalid array inputs" do
      assert {:error, [[message: _, index: 0, path: [0]]]} =
               Ash.Type.cast_input({:array, ChDecimal}, ["invalid", Decimal.new("123.45")],
                 items: [precision: 5, scale: 2]
               )
    end
  end

  describe "cast_stored/2" do
    test "casts stored string to Decimal" do
      assert ChDecimal.cast_stored("123.45", precision: 10, scale: 2) ==
               {:ok, Decimal.new("123.45")}

      assert ChDecimal.cast_stored(nil, []) == {:ok, nil}
    end

    test "returns error for non-string stored values" do
      assert :error = ChDecimal.cast_stored("any", precision: 10, scale: 2)
    end

    test "casts stored arrays of strings to Decimals" do
      assert Ash.Type.cast_stored({:array, ChDecimal}, ["123.45", "678.90"],
               precision: 10,
               scale: 2
             ) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.90")]}

      assert Ash.Type.cast_stored({:array, ChDecimal}, [nil, "123.45"], precision: 10, scale: 2) ==
               {:ok, [nil, Decimal.new("123.45")]}
    end

    test "returns error for non-string array stored values" do
      assert {:error, [{:index, 0}]} =
               Ash.Type.cast_stored({:array, ChDecimal}, ["any", "123.45"],
                 precision: 10,
                 scale: 2
               )
    end
  end

  describe "equal?/2" do
    test "returns true for equal Decimal structs" do
      decimal = Decimal.new("123.45")
      assert Ash.Type.equal?(ChDecimal, decimal, decimal)
      assert Ash.Type.equal?(ChDecimal, nil, nil)
    end

    test "returns false for different Decimal structs" do
      refute Ash.Type.equal?(ChDecimal, Decimal.new("123.45"), Decimal.new("678.90"))
      refute Ash.Type.equal?(ChDecimal, Decimal.new("123.45"), nil)
      refute Ash.Type.equal?(ChDecimal, nil, Decimal.new("123.45"))
    end

    test "returns true for equal arrays of Decimal structs" do
      decimal1 = Decimal.new("123.45")
      decimal2 = Decimal.new("678.90")
      assert Ash.Type.equal?({:array, ChDecimal}, [decimal1, decimal2], [decimal1, decimal2])
      assert Ash.Type.equal?({:array, ChDecimal}, [], [])
    end

    test "returns false for different arrays of Decimal structs" do
      decimal1 = Decimal.new("123.45")
      decimal2 = Decimal.new("678.90")
      refute Ash.Type.equal?({:array, ChDecimal}, [decimal1, decimal2], [decimal2, decimal1])
      refute Ash.Type.equal?({:array, ChDecimal}, [decimal1], [decimal1, decimal2])
      refute Ash.Type.equal?({:array, ChDecimal}, [decimal1, nil], [decimal1, decimal2])
    end
  end
end
