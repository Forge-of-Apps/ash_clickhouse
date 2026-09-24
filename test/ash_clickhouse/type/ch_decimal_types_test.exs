defmodule AshClickhouse.Type.ChDecimalTypesTest do
  use ExUnit.Case, async: true

  alias AshClickhouse.Type.ChDecimal32
  alias AshClickhouse.Type.ChDecimal64
  alias AshClickhouse.Type.ChDecimal128
  alias AshClickhouse.Type.ChDecimal256

  import AshClickhouse.Test.Helper, only: [encode_ch_type: 1]

  describe "storage_types" do
    test "returns correct ClickHouse types for Decimal32" do
      assert {:parameterized, {Ch, {:decimal32, 3}}} =
               type = Ash.Type.storage_type(ChDecimal32, scale: 3)

      assert encode_ch_type(type) == "Decimal(9, 3)"
    end

    test "returns correct ClickHouse types for Nullable(Decimal32)" do
      assert {:parameterized, {Ch, {:nullable, {:decimal32, 4}}}} =
               type = Ash.Type.storage_type(ChDecimal32, scale: 4, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Decimal(9, 4))"
    end

    test "returns correct ClickHouse types for Decimal64" do
      assert {:parameterized, {Ch, {:decimal64, 2}}} =
               type = Ash.Type.storage_type(ChDecimal64, scale: 2)

      assert encode_ch_type(type) == "Decimal(18, 2)"
    end

    test "returns correct ClickHouse types for Nullable(Decimal64)" do
      assert {:parameterized, {Ch, {:nullable, {:decimal64, 6}}}} =
               type = Ash.Type.storage_type(ChDecimal64, scale: 6, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Decimal(18, 6))"
    end

    test "returns correct ClickHouse types for Decimal128" do
      assert {:parameterized, {Ch, {:decimal128, 5}}} =
               type = Ash.Type.storage_type(ChDecimal128, scale: 5)

      assert encode_ch_type(type) == "Decimal(38, 5)"
    end

    test "returns correct ClickHouse types for Nullable(Decimal128)" do
      assert {:parameterized, {Ch, {:nullable, {:decimal128, 7}}}} =
               type = Ash.Type.storage_type(ChDecimal128, scale: 7, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Decimal(38, 7))"
    end

    test "returns correct ClickHouse types for Decimal256" do
      assert {:parameterized, {Ch, {:decimal256, 8}}} =
               type = Ash.Type.storage_type(ChDecimal256, scale: 8)

      assert encode_ch_type(type) == "Decimal(76, 8)"
    end

    test "returns correct ClickHouse types for Nullable(Decimal256)" do
      assert {:parameterized, {Ch, {:nullable, {:decimal256, 9}}}} =
               type = Ash.Type.storage_type(ChDecimal256, scale: 9, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Decimal(76, 9))"
    end

    test "returns correct ClickHouse types for array version of Decimal32" do
      assert {:array, {:parameterized, {Ch, {:decimal32, 3}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal32}, items: [scale: 3])

      assert encode_ch_type({:array, subtype}) == "Array(Decimal(9, 3))"
    end

    test "returns correct ClickHouse types for Nullable array version of Decimal32" do
      assert {:array, {:parameterized, {Ch, {:nullable, {:decimal32, 4}}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal32}, items: [scale: 4, nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Decimal(9, 4)))"
    end

    test "returns correct ClickHouse types for array version of Decimal64" do
      assert {:array, {:parameterized, {Ch, {:decimal64, 2}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal64}, items: [scale: 2])

      assert encode_ch_type({:array, subtype}) == "Array(Decimal(18, 2))"
    end

    test "returns correct ClickHouse types for Nullable array version of Decimal64" do
      assert {:array, {:parameterized, {Ch, {:nullable, {:decimal64, 6}}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal64}, items: [scale: 6, nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Decimal(18, 6)))"
    end

    test "returns correct ClickHouse types for array version of Decimal128" do
      assert {:array, {:parameterized, {Ch, {:decimal128, 5}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal128}, items: [scale: 5])

      assert encode_ch_type({:array, subtype}) == "Array(Decimal(38, 5))"
    end

    test "returns correct ClickHouse types for Nullable array version of Decimal128" do
      assert {:array, {:parameterized, {Ch, {:nullable, {:decimal128, 7}}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal128}, items: [scale: 7, nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Decimal(38, 7)))"
    end

    test "returns correct ClickHouse types for array version of Decimal256" do
      assert {:array, {:parameterized, {Ch, {:decimal256, 8}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal256}, items: [scale: 8])

      assert encode_ch_type({:array, subtype}) == "Array(Decimal(76, 8))"
    end

    test "returns correct ClickHouse types for Nullable array version of Decimal256" do
      assert {:array, {:parameterized, {Ch, {:nullable, {:decimal256, 9}}}} = subtype} =
               Ash.Type.storage_type({:array, ChDecimal256}, items: [scale: 9, nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Decimal(76, 9)))"
    end
  end

  describe "matches_type?/2" do
    test "returns true for Decimal structs" do
      assert Ash.Type.matches_type?(ChDecimal32, Decimal.new("123.456"), [])
      assert Ash.Type.matches_type?(ChDecimal64, Decimal.new("1234567890.12"), [])
      assert Ash.Type.matches_type?(ChDecimal128, Decimal.new("12345678901234567890.12345"), [])

      assert Ash.Type.matches_type?(
               ChDecimal256,
               Decimal.new("123456789012345678901234567890.12345678", max_digits: 76),
               []
             )
    end

    test "returns false for non-Decimal values" do
      refute Ash.Type.matches_type?(ChDecimal32, nil, [])
      refute Ash.Type.matches_type?(ChDecimal64, 123.45, [])
      refute Ash.Type.matches_type?(ChDecimal128, "123.45", [])
      refute Ash.Type.matches_type?(ChDecimal256, [], [])
    end

    test "returns true for arrays of Decimal structs" do
      assert Ash.Type.matches_type?(
               {:array, ChDecimal32},
               [Decimal.new("123.456"), Decimal.new("789.012")],
               []
             )

      assert Ash.Type.matches_type?(
               {:array, ChDecimal64},
               [Decimal.new("1234567890.12"), Decimal.new("9876543210.98")],
               []
             )

      assert Ash.Type.matches_type?(
               {:array, ChDecimal128},
               [
                 Decimal.new("12345678901234567890.12345"),
                 Decimal.new("98765432109876543210.98765")
               ],
               []
             )

      assert Ash.Type.matches_type?(
               {:array, ChDecimal256},
               [
                 Decimal.new("123456789012345678901234567890.12345678", max_digits: 76),
                 Decimal.new("987654321098765432109876543210.87654321", max_digits: 76)
               ],
               []
             )
    end

    test "returns false for non-Decimal arrays" do
      refute Ash.Type.matches_type?({:array, ChDecimal32}, [123.45, 678.90], [])
      refute Ash.Type.matches_type?({:array, ChDecimal64}, ["123.45", "678.90"], [])
      refute Ash.Type.matches_type?({:array, ChDecimal128}, [[], {}], [])
      refute Ash.Type.matches_type?({:array, ChDecimal256}, [nil, 123], [])
    end
  end

  describe "generator" do
    test "Decimal32: generates Decimal structs within specified constraints" do
      constraints = [min: Decimal.new("1.00"), max: Decimal.new("10.00")]

      generated_decimals =
        Enum.take(Ash.Type.generator(ChDecimal32, constraints), 100) |> Enum.uniq()

      assert Enum.all?(generated_decimals, fn decimal ->
               Decimal.compare(decimal, constraints[:min]) != :lt and
                 Decimal.compare(decimal, constraints[:max]) != :gt
             end)
    end

    test "Decimal64: generates Decimal structs within specified constraints" do
      constraints = [min: Decimal.new("100.00"), max: Decimal.new("200.00")]

      generated_decimals =
        Enum.take(Ash.Type.generator(ChDecimal64, constraints), 100) |> Enum.uniq()

      assert Enum.all?(generated_decimals, fn decimal ->
               Decimal.compare(decimal, constraints[:min]) != :lt and
                 Decimal.compare(decimal, constraints[:max]) != :gt
             end)
    end

    test "Decimal128: generates Decimal structs within specified constraints" do
      constraints = [min: Decimal.new("1000.00"), max: Decimal.new("2000.00")]

      generated_decimals =
        Enum.take(Ash.Type.generator(ChDecimal128, constraints), 100) |> Enum.uniq()

      assert Enum.all?(generated_decimals, fn decimal ->
               Decimal.compare(decimal, constraints[:min]) != :lt and
                 Decimal.compare(decimal, constraints[:max]) != :gt
             end)
    end

    test "Decimal256: generates Decimal structs within specified constraints" do
      constraints = [min: Decimal.new("10000.00"), max: Decimal.new("20000.00")]

      generated_decimals =
        Enum.take(Ash.Type.generator(ChDecimal256, constraints), 100) |> Enum.uniq()

      assert Enum.all?(generated_decimals, fn decimal ->
               Decimal.compare(decimal, constraints[:min]) != :lt and
                 Decimal.compare(decimal, constraints[:max]) != :gt
             end)
    end

    test "Decimal32: generates arrays of Decimal structs within specified constraints" do
      constraints = [scale: 2, min: Decimal.new("1.00"), max: Decimal.new("10.00")]

      generated_arrays =
        Enum.take(Ash.Type.generator({:array, ChDecimal32}, items: constraints), 100)

      assert Enum.all?(generated_arrays, fn arr ->
               is_list(arr) and
                 Enum.all?(arr, fn decimal ->
                   Decimal.compare(decimal, constraints[:min]) != :lt and
                     Decimal.compare(decimal, constraints[:max]) != :gt
                 end)
             end)
    end

    test "Decimal64: generates arrays of Decimal structs within specified constraints" do
      constraints = [scale: 2, min: Decimal.new("100.00"), max: Decimal.new("200.00")]

      generated_arrays =
        Enum.take(Ash.Type.generator({:array, ChDecimal64}, items: constraints), 100)

      assert Enum.all?(generated_arrays, fn arr ->
               is_list(arr) and
                 Enum.all?(arr, fn decimal ->
                   Decimal.compare(decimal, constraints[:min]) != :lt and
                     Decimal.compare(decimal, constraints[:max]) != :gt
                 end)
             end)
    end

    test "Decimal128: generates arrays of Decimal structs within specified constraints" do
      constraints = [scale: 2, min: Decimal.new("1000.00"), max: Decimal.new("2000.00")]

      generated_arrays =
        Enum.take(Ash.Type.generator({:array, ChDecimal128}, items: constraints), 100)

      assert Enum.all?(generated_arrays, fn arr ->
               is_list(arr) and
                 Enum.all?(arr, fn decimal ->
                   Decimal.compare(decimal, constraints[:min]) != :lt and
                     Decimal.compare(decimal, constraints[:max]) != :gt
                 end)
             end)
    end

    test "Decimal256: generates arrays of Decimal structs within specified constraints" do
      constraints = [scale: 2, min: Decimal.new("10000.00"), max: Decimal.new("20000.00")]

      generated_arrays =
        Enum.take(Ash.Type.generator({:array, ChDecimal256}, items: constraints), 100)

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

      assert Ash.Type.apply_constraints(ChDecimal32, Decimal.new("10.00"), constraints) ==
               {:ok, Decimal.new("10.00")}

      assert Ash.Type.apply_constraints(ChDecimal64, Decimal.new("10.00"), constraints) ==
               {:ok, Decimal.new("10.00")}

      assert Ash.Type.apply_constraints(ChDecimal128, Decimal.new("10.00"), constraints) ==
               {:ok, Decimal.new("10.00")}

      assert Ash.Type.apply_constraints(ChDecimal256, Decimal.new("10.00"), constraints) ==
               {:ok, Decimal.new("10.00")}
    end

    test "returns error for Decimal below min constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      {:error, errors32} =
        Ash.Type.apply_constraints(ChDecimal32, Decimal.new("3.00"), constraints)

      {:error, errors64} =
        Ash.Type.apply_constraints(ChDecimal64, Decimal.new("3.00"), constraints)

      {:error, errors128} =
        Ash.Type.apply_constraints(ChDecimal128, Decimal.new("3.00"), constraints)

      {:error, errors256} =
        Ash.Type.apply_constraints(ChDecimal256, Decimal.new("3.00"), constraints)

      expected_error = [
        [message: "must be more than or equal to %{min}", min: Decimal.new("5.00")]
      ]

      assert errors32 == expected_error
      assert errors64 == expected_error
      assert errors128 == expected_error
      assert errors256 == expected_error
    end

    test "returns error for Decimal above max constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      {:error, errors32} =
        Ash.Type.apply_constraints(ChDecimal32, Decimal.new("20.00"), constraints)

      {:error, errors64} =
        Ash.Type.apply_constraints(ChDecimal64, Decimal.new("20.00"), constraints)

      {:error, errors128} =
        Ash.Type.apply_constraints(ChDecimal128, Decimal.new("20.00"), constraints)

      {:error, errors256} =
        Ash.Type.apply_constraints(ChDecimal256, Decimal.new("20.00"), constraints)

      expected_error = [
        [message: "must be less than or equal to %{max}", max: Decimal.new("15.00")]
      ]

      assert errors32 == expected_error
      assert errors64 == expected_error
      assert errors128 == expected_error
      assert errors256 == expected_error
    end

    test "returns ok for valid array of Decimals within constraints" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      assert Ash.Type.apply_constraints(
               {:array, ChDecimal32},
               [Decimal.new("10.00"), Decimal.new("12.00")],
               items: constraints
             ) ==
               {:ok, [Decimal.new("10.00"), Decimal.new("12.00")]}

      assert Ash.Type.apply_constraints(
               {:array, ChDecimal64},
               [Decimal.new("10.00"), Decimal.new("12.00")],
               items: constraints
             ) ==
               {:ok, [Decimal.new("10.00"), Decimal.new("12.00")]}

      assert Ash.Type.apply_constraints(
               {:array, ChDecimal128},
               [Decimal.new("10.00"), Decimal.new("12.00")],
               items: constraints
             ) ==
               {:ok, [Decimal.new("10.00"), Decimal.new("12.00")]}

      assert Ash.Type.apply_constraints(
               {:array, ChDecimal256},
               [Decimal.new("10.00"), Decimal.new("12.00")],
               items: constraints
             ) ==
               {:ok, [Decimal.new("10.00"), Decimal.new("12.00")]}
    end

    test "returns error for array with Decimal below min constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      {:error, errors32} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal32},
          [Decimal.new("10.00"), Decimal.new("3.00")],
          items: constraints
        )

      {:error, errors64} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal64},
          [Decimal.new("10.00"), Decimal.new("3.00")],
          items: constraints
        )

      {:error, errors128} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal128},
          [Decimal.new("10.00"), Decimal.new("3.00")],
          items: constraints
        )

      {:error, errors256} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal256},
          [Decimal.new("10.00"), Decimal.new("3.00")],
          items: constraints
        )

      expected_error = [
        [index: 1, message: "must be more than or equal to %{min}", min: Decimal.new("5.00")]
      ]

      assert errors32 == expected_error
      assert errors64 == expected_error
      assert errors128 == expected_error
      assert errors256 == expected_error
    end

    test "returns error for array with Decimal above max constraint" do
      constraints = [min: Decimal.new("5.00"), max: Decimal.new("15.00")]

      {:error, errors32} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal32},
          [Decimal.new("10.00"), Decimal.new("20.00")],
          items: constraints
        )

      {:error, errors64} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal64},
          [Decimal.new("10.00"), Decimal.new("20.00")],
          items: constraints
        )

      {:error, errors128} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal128},
          [Decimal.new("10.00"), Decimal.new("20.00")],
          items: constraints
        )

      {:error, errors256} =
        Ash.Type.apply_constraints(
          {:array, ChDecimal256},
          [Decimal.new("10.00"), Decimal.new("20.00")],
          items: constraints
        )

      expected_error = [
        [index: 1, message: "must be less than or equal to %{max}", max: Decimal.new("15.00")]
      ]

      assert errors32 == expected_error
      assert errors64 == expected_error
      assert errors128 == expected_error
      assert errors256 == expected_error
    end
  end

  describe "string casts beyond decimal128 precision" do
    test "each type parses as many digits as its column holds" do
      digits38 = String.duplicate("9", 36) <> ".99"
      digits76 = String.duplicate("9", 74) <> ".99"

      assert {:ok, %Decimal{}} = Ash.Type.cast_input(ChDecimal128, digits38, scale: 2)
      assert {:ok, %Decimal{}} = Ash.Type.cast_stored(ChDecimal128, digits38, scale: 2)
      assert {:ok, %Decimal{}} = Ash.Type.cast_input(ChDecimal256, digits76, scale: 2)
      assert {:ok, %Decimal{}} = Ash.Type.cast_stored(ChDecimal256, digits76, scale: 2)
      assert %Decimal{} = ChDecimal256.new(digits76)
    end

    test "digits beyond the column's range are rejected" do
      assert {:error, _} = Ash.Type.cast_input(ChDecimal32, String.duplicate("9", 10), scale: 0)
      assert :error = Ash.Type.cast_stored(ChDecimal128, String.duplicate("9", 39), scale: 0)
    end
  end

  describe "cast_input/2" do
    test "casts valid Decimal correctly" do
      assert Ash.Type.cast_input(ChDecimal32, Decimal.new("123.45"), precision: 9, scale: 2) ==
               {:ok, Decimal.new("123.45")}

      assert Ash.Type.cast_input(ChDecimal64, "678.90", precision: 18, scale: 2) ==
               {:ok, Decimal.new("678.90")}

      assert Ash.Type.cast_input(ChDecimal128, 123.45, precision: 38, scale: 2) ==
               {:ok, Decimal.new("123.45")}

      assert Ash.Type.cast_input(ChDecimal256, nil, precision: 76, scale: 2) == {:ok, nil}
    end

    test "returns error for invalid inputs" do
      assert Ash.Type.cast_input(ChDecimal32, "invalid", []) == {:error, "is invalid"}
      assert Ash.Type.cast_input(ChDecimal64, "invalid", []) == {:error, "is invalid"}
      assert Ash.Type.cast_input(ChDecimal128, "invalid", []) == {:error, "is invalid"}
      assert Ash.Type.cast_input(ChDecimal256, "invalid", []) == {:error, "is invalid"}
    end

    test "casts valid array of Decimals correctly" do
      assert Ash.Type.cast_input(
               {:array, ChDecimal32},
               [Decimal.new("123.45"), Decimal.new("678.90")],
               items: [scale: 2]
             ) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.90")]}

      assert Ash.Type.cast_input({:array, ChDecimal64}, ["1234567890.12", "9876543210.98"],
               items: [scale: 2]
             ) ==
               {:ok, [Decimal.new("1234567890.12"), Decimal.new("9876543210.98")]}

      assert Ash.Type.cast_input({:array, ChDecimal128}, [123.45, 678.90], items: [scale: 2]) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.9")]}

      assert Ash.Type.cast_input({:array, ChDecimal256}, [nil, Decimal.new("123.45")],
               items: [scale: 2]
             ) ==
               {:ok, [nil, Decimal.new("123.45")]}
    end

    test "returns error for invalid array inputs" do
      assert {:error, [[message: "is invalid", index: 0, path: [0]]]} =
               Ash.Type.cast_input({:array, ChDecimal32}, ["invalid", Decimal.new("123.45")],
                 items: [scale: 2]
               )

      assert {:error, [[message: "is invalid", index: 0, path: [0]]]} =
               Ash.Type.cast_input({:array, ChDecimal64}, ["invalid", Decimal.new("123.45")],
                 items: [scale: 2]
               )

      assert {:error, [[message: "is invalid", index: 0, path: [0]]]} =
               Ash.Type.cast_input({:array, ChDecimal128}, ["invalid", Decimal.new("123.45")],
                 items: [scale: 2]
               )

      assert {:error, [[message: "is invalid", index: 0, path: [0]]]} =
               Ash.Type.cast_input({:array, ChDecimal256}, ["invalid", Decimal.new("123.45")],
                 items: [scale: 2]
               )
    end
  end

  describe "cast_stored/2" do
    test "casts stored string to Decimal" do
      assert Ash.Type.cast_stored(ChDecimal32, "123.45", precision: 9, scale: 2) ==
               {:ok, Decimal.new("123.45")}

      assert Ash.Type.cast_stored(ChDecimal64, "1234567890.12", precision: 18, scale: 2) ==
               {:ok, Decimal.new("1234567890.12")}

      assert Ash.Type.cast_stored(ChDecimal128, "12345678901234567890.12345",
               precision: 38,
               scale: 5
             ) ==
               {:ok, Decimal.new("12345678901234567890.12345")}

      assert Ash.Type.cast_stored(ChDecimal256, nil, []) == {:ok, nil}
    end

    test "returns error for non-string stored values" do
      assert :error = Ash.Type.cast_stored(ChDecimal32, "any", precision: 9, scale: 2)
      assert :error = Ash.Type.cast_stored(ChDecimal64, "any", precision: 18, scale: 2)
      assert :error = Ash.Type.cast_stored(ChDecimal128, "any", precision: 38, scale: 5)
      assert :error = Ash.Type.cast_stored(ChDecimal256, "any", precision: 76, scale: 8)
    end

    test "casts stored arrays of strings to Decimals" do
      assert Ash.Type.cast_stored({:array, ChDecimal32}, ["123.45", "678.90"], items: [scale: 2]) ==
               {:ok, [Decimal.new("123.45"), Decimal.new("678.90")]}

      assert Ash.Type.cast_stored({:array, ChDecimal64}, ["1234567890.12", "9876543210.98"],
               items: [scale: 2]
             ) ==
               {:ok, [Decimal.new("1234567890.12"), Decimal.new("9876543210.98")]}

      assert Ash.Type.cast_stored(
               {:array, ChDecimal128},
               ["12345678901234567890.12345", "98765432109876543210.98765"],
               items: [scale: 5]
             ) ==
               {:ok,
                [
                  Decimal.new("12345678901234567890.12345"),
                  Decimal.new("98765432109876543210.98765")
                ]}

      assert Ash.Type.cast_stored({:array, ChDecimal256}, [nil, "123.45"], items: [scale: 2]) ==
               {:ok, [nil, Decimal.new("123.45")]}
    end

    test "returns error for non-string array stored values" do
      assert {:error, [{:index, 0}]} =
               Ash.Type.cast_stored({:array, ChDecimal32}, ["any", "123.45"], items: [scale: 2])

      assert {:error, [{:index, 0}]} =
               Ash.Type.cast_stored({:array, ChDecimal64}, ["any", "123.45"], items: [scale: 2])

      assert {:error, [{:index, 0}]} =
               Ash.Type.cast_stored({:array, ChDecimal128}, ["any", "123.45"], items: [scale: 5])

      assert {:error, [{:index, 0}]} =
               Ash.Type.cast_stored({:array, ChDecimal256}, ["any", "123.45"], items: [scale: 8])
    end
  end

  describe "equal?/2" do
    test "returns true for equal Decimal structs" do
      decimal32 = Decimal.new("123.456")
      decimal64 = Decimal.new("1234567890.12")
      decimal128 = Decimal.new("12345678901234567890.12345")
      decimal256 = Decimal.new("123456789012345678901234567890.12345678", max_digits: 76)

      assert Ash.Type.equal?(ChDecimal32, decimal32, decimal32)
      assert Ash.Type.equal?(ChDecimal64, decimal64, decimal64)
      assert Ash.Type.equal?(ChDecimal128, decimal128, decimal128)
      assert Ash.Type.equal?(ChDecimal256, decimal256, decimal256)
      assert Ash.Type.equal?(ChDecimal32, nil, nil)
      assert Ash.Type.equal?(ChDecimal64, nil, nil)
      assert Ash.Type.equal?(ChDecimal128, nil, nil)
      assert Ash.Type.equal?(ChDecimal256, nil, nil)
    end

    test "returns false for different Decimal structs" do
      refute Ash.Type.equal?(ChDecimal32, Decimal.new("123.456"), Decimal.new("789.012"))

      refute Ash.Type.equal?(
               ChDecimal64,
               Decimal.new("1234567890.12"),
               Decimal.new("9876543210.98")
             )

      refute Ash.Type.equal?(ChDecimal32, Decimal.new("123.456"), nil)
      refute Ash.Type.equal?(ChDecimal64, nil, Decimal.new("1234567890.12"))
    end

    test "returns true for equal arrays of Decimal structs" do
      decimal32_1 = Decimal.new("123.456")
      decimal32_2 = Decimal.new("789.012")
      decimal64_1 = Decimal.new("1234567890.12")
      decimal64_2 = Decimal.new("9876543210.98")

      assert Ash.Type.equal?({:array, ChDecimal32}, [decimal32_1, decimal32_2], [
               decimal32_1,
               decimal32_2
             ])

      assert Ash.Type.equal?({:array, ChDecimal64}, [decimal64_1, decimal64_2], [
               decimal64_1,
               decimal64_2
             ])

      assert Ash.Type.equal?({:array, ChDecimal32}, [], [])
      assert Ash.Type.equal?({:array, ChDecimal64}, [], [])
    end

    test "returns false for different arrays of Decimal structs" do
      decimal32_1 = Decimal.new("123.456")
      decimal32_2 = Decimal.new("789.012")
      decimal64_1 = Decimal.new("1234567890.12")
      decimal64_2 = Decimal.new("9876543210.98")

      refute Ash.Type.equal?({:array, ChDecimal32}, [decimal32_1, decimal32_2], [
               decimal32_2,
               decimal32_1
             ])

      refute Ash.Type.equal?({:array, ChDecimal64}, [decimal64_1, decimal64_2], [
               decimal64_2,
               decimal64_1
             ])

      refute Ash.Type.equal?({:array, ChDecimal32}, [decimal32_1], [decimal32_1, decimal32_2])

      refute Ash.Type.equal?({:array, ChDecimal64}, [decimal64_1, nil], [decimal64_1, decimal64_2])
    end
  end
end
