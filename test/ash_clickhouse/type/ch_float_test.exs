defmodule AshClickhouse.Type.ChFloatTest do
  use ExUnit.Case, async: true
  alias AshClickhouse.Type.ChFloat32
  alias AshClickhouse.Type.ChFloat64

  import AshClickhouse.Test.Helper, only: [encode_ch_type: 1]

  describe "storage_types" do
    test "returns correct ClickHouse type without constraints" do
      assert {:parameterized, {Ch, :f32}} = type = Ash.Type.storage_type(ChFloat32, [])
      assert encode_ch_type(type) == "Float32"

      assert {:parameterized, {Ch, :f64}} = type = Ash.Type.storage_type(ChFloat64, [])
      assert encode_ch_type(type) == "Float64"
    end

    test "returns nullable ClickHouse type with nullable constraint" do
      assert {:parameterized, {Ch, {:nullable, :f32}}} =
               type =
               Ash.Type.storage_type(ChFloat32, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Float32)"

      assert {:parameterized, {Ch, {:nullable, :f64}}} =
               type =
               Ash.Type.storage_type(ChFloat64, nullable?: true)

      assert encode_ch_type(type) == "Nullable(Float64)"
    end

    test "returns correct ClickHouse type without constraints for array version" do
      assert {:array, {:parameterized, {Ch, :f32}} = subtype} =
               Ash.Type.storage_type({:array, ChFloat32}, [])

      assert encode_ch_type({:array, subtype}) == "Array(Float32)"

      assert {:array, {:parameterized, {Ch, :f64}} = subtype} =
               Ash.Type.storage_type({:array, ChFloat64}, [])

      assert encode_ch_type({:array, subtype}) == "Array(Float64)"
    end

    test "returns nullable ClickHouse type with nullable constraint for array version" do
      assert {:array, {:parameterized, {Ch, {:nullable, :f32}}} = subtype} =
               Ash.Type.storage_type({:array, ChFloat32}, items: [nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Float32))"

      assert {:array, {:parameterized, {Ch, {:nullable, :f64}}} = subtype} =
               Ash.Type.storage_type({:array, ChFloat64}, items: [nullable?: true])

      assert encode_ch_type({:array, subtype}) == "Array(Nullable(Float64))"
    end
  end

  describe "matches_type?/2" do
    test "returns true for floats" do
      assert Ash.Type.matches_type?(ChFloat32, 3.14, [])
      assert Ash.Type.matches_type?(ChFloat64, 2.71828, [])
    end

    test "returns false for non-floats" do
      refute Ash.Type.matches_type?(ChFloat32, 123, [])
      refute Ash.Type.matches_type?(ChFloat64, "string", [])
      refute Ash.Type.matches_type?(ChFloat32, nil, [])
      refute Ash.Type.matches_type?(ChFloat64, nil, [])
      refute Ash.Type.matches_type?(ChFloat32, [], [])
    end

    test "returns true for arrays of floats" do
      assert Ash.Type.matches_type?({:array, ChFloat32}, [3.14, 2.71], [])
      assert Ash.Type.matches_type?({:array, ChFloat64}, [1.618, 2.718], [])
    end

    test "returns false for non-float arrays" do
      refute Ash.Type.matches_type?({:array, ChFloat32}, [123, 456], [])
      refute Ash.Type.matches_type?({:array, ChFloat64}, ["string", "test"], [])
      refute Ash.Type.matches_type?({:array, ChFloat32}, [[], {}], [])
    end
  end

  describe "generator" do
    test "Foat32: generates floats within min and max" do
      [
        [min: -10.0, max: 10.0],
        [min: 0.0, max: 1.0],
        [min: -1.0, max: 0.0]
      ]
      |> Enum.each(fn constraints ->
        generated_floats = Enum.take(Ash.Type.generator(ChFloat32, constraints), 100)

        assert Enum.all?(generated_floats, fn value ->
                 value >= constraints[:min] and value <= constraints[:max]
               end)
      end)
    end

    test "Float32 generate floats within greater_than and less_than" do
      [
        [greater_than: -5.0, less_than: 5.0],
        [greater_than: 0.0, less_than: 2.0],
        [greater_than: -2.0, less_than: 0.0]
      ]
      |> Enum.each(fn constraints ->
        generated_floats = Enum.take(Ash.Type.generator(ChFloat32, constraints), 100)

        assert Enum.all?(generated_floats, fn value ->
                 value > constraints[:greater_than] and value < constraints[:less_than]
               end)
      end)
    end

    test "Float64: generates floats within specified constraints" do
      [
        [min: -1.0, max: 1.0],
        [min: 1.05, max: 1.55],
        [min: -2.25, max: -1.75]
      ]
      |> Enum.each(fn constraints ->
        generated_floats = Enum.take(Ash.Type.generator(ChFloat64, constraints), 100)

        assert Enum.all?(generated_floats, fn value ->
                 value >= constraints[:min] and value <= constraints[:max]
               end)
      end)
    end

    test "Float64 generate floats within greater_than and less_than" do
      [
        [greater_than: -100.0005, less_than: -1.0010],
        [greater_than: 100.2345, less_than: 1000.2350],
        [greater_than: -200.255, less_than: -2.250]
      ]
      |> Enum.each(fn constraints ->
        generated_floats = Enum.take(Ash.Type.generator(ChFloat64, constraints), 100)

        assert Enum.all?(generated_floats, fn value ->
                 value > constraints[:greater_than] and value < constraints[:less_than]
               end)
      end)
    end

    test "generates arrays of floats within min and max" do
      [
        [min: -10.0, max: 10.0],
        [min: 0.0, max: 1.0],
        [min: -1.0, max: 0.0]
      ]
      |> Enum.each(fn constraints ->
        Enum.each(
          [ChFloat32, ChFloat64],
          fn module ->
            generated_arrays =
              Enum.take(Ash.Type.generator({:array, module}, items: constraints), 100)

            assert Enum.all?(generated_arrays, fn arr ->
                     is_list(arr) and
                       Enum.all?(arr, fn value ->
                         value >= constraints[:min] and value <= constraints[:max]
                       end)
                   end)
          end
        )
      end)
    end

    test "generates arrays of floats within greater_than and less_than" do
      [
        [greater_than: -5.0, less_than: 5.0],
        [greater_than: 0.0, less_than: 2.0],
        [greater_than: -2.0, less_than: 0.0]
      ]
      |> Enum.each(fn constraints ->
        Enum.each(
          [ChFloat32, ChFloat64],
          fn module ->
            generated_arrays =
              Enum.take(Ash.Type.generator({:array, module}, items: constraints), 100)

            assert Enum.all?(generated_arrays, fn arr ->
                     is_list(arr) and
                       Enum.all?(arr, fn value ->
                         value > constraints[:greater_than] and value < constraints[:less_than]
                       end)
                   end)
          end
        )
      end)
    end

    test "draws a first float between greater_than and less_than every time" do
      for module <- [ChFloat32, ChFloat64],
          constraints <- [
            [greater_than: 100.2345, less_than: 1000.2350],
            [greater_than: -1.0, less_than: 0.0],
            [greater_than: 0.0, less_than: 1.0e-300]
          ] do
        firsts =
          for _ <- 1..2_000,
              do: module |> Ash.Type.generator(constraints) |> Enum.take(1) |> hd()

        assert Enum.all?(
                 firsts,
                 &(&1 > constraints[:greater_than] and &1 < constraints[:less_than])
               )
      end
    end

    test "draws the floats next to greater_than and less_than, never the bounds" do
      firsts =
        for _ <- 1..200,
            do:
              ChFloat64
              |> Ash.Type.generator(greater_than: 1.0, less_than: 2.0)
              |> Enum.take(1)
              |> hd()

      assert 1.0000000000000002 in firsts
      assert 1.9999999999999998 in firsts
      refute 1.0 in firsts
      refute 2.0 in firsts
    end

    test "keeps to the tighter of min and greater_than, and of max and less_than" do
      values =
        ChFloat64
        |> Ash.Type.generator(min: 0.0, greater_than: 0.5, max: 2.0, less_than: 1.0)
        |> Enum.take(500)

      assert Enum.all?(values, &(&1 > 0.5 and &1 < 1.0))
    end
  end

  describe "apply_constraints/2" do
    test "returns ok for valid float within constraints" do
      assert Ash.Type.apply_constraints(ChFloat32, 5.0, min: 0.0, max: 10.0) == {:ok, 5.0}

      assert Ash.Type.apply_constraints(ChFloat64, -1.5, greater_than: -2.0, less_than: 0.0) ==
               {:ok, -1.5}
    end

    test "returns error for float outside constraints" do
      {:error, errors} = Ash.Type.apply_constraints(ChFloat32, 15.0, min: 0.0, max: 10.0)
      assert length(errors) == 1

      {:error, errors} =
        Ash.Type.apply_constraints(ChFloat64, -3.0, greater_than: -2.0, less_than: 0.0)

      assert length(errors) == 1
    end

    test "returns ok for nil value" do
      assert Ash.Type.apply_constraints(ChFloat32, nil, min: 0.0, max: 10.0) == {:ok, nil}

      assert Ash.Type.apply_constraints(ChFloat64, nil, greater_than: -2.0, less_than: 0.0) ==
               {:ok, nil}
    end

    test "returns ok for valid array of floats within constraints" do
      assert Ash.Type.apply_constraints({:array, ChFloat32}, [5.0, 7.5],
               items: [min: 0.0, max: 10.0]
             ) ==
               {:ok, [5.0, 7.5]}

      assert Ash.Type.apply_constraints({:array, ChFloat64}, [-1.5, -0.5],
               items: [greater_than: -2.0, less_than: 0.0]
             ) ==
               {:ok, [-1.5, -0.5]}
    end

    test "returns error for array with float outside constraints" do
      {:error, errors} =
        Ash.Type.apply_constraints({:array, ChFloat32}, [5.0, 15.0], items: [min: 0.0, max: 10.0])

      assert length(errors) == 1

      {:error, errors} =
        Ash.Type.apply_constraints({:array, ChFloat64}, [-1.5, -3.0],
          items: [greater_than: -2.0, less_than: 0.0]
        )

      assert length(errors) == 1
    end
  end

  describe "cast_input/2" do
    test "casts valid array of floats correctly" do
      assert Ash.Type.cast_input({:array, ChFloat32}, [3.14, 2.71], []) == {:ok, [3.14, 2.71]}
      assert Ash.Type.cast_input({:array, ChFloat64}, [1.618, 2.718], []) == {:ok, [1.618, 2.718]}
      assert Ash.Type.cast_input({:array, ChFloat32}, [nil, 3.14], []) == {:ok, [nil, 3.14]}
    end

    test "returns error for non-float array inputs" do
      assert {:error, [[message: "is invalid", index: 0, path: [0]]]} =
               Ash.Type.cast_input({:array, ChFloat32}, ["string", 3.14], [])

      assert {:error, [[message: "is invalid", index: 1, path: [1]]]} =
               Ash.Type.cast_input({:array, ChFloat64}, [2.718, []], [])
    end
  end

  describe "equal?/2" do
    test "returns true for equal floats" do
      assert Ash.Type.equal?(ChFloat32, 3.14, 3.14)
      assert Ash.Type.equal?(ChFloat64, 2.718, 2.718)
      assert Ash.Type.equal?(ChFloat32, nil, nil)
      assert Ash.Type.equal?(ChFloat64, nil, nil)
    end

    test "returns false for different floats" do
      refute Ash.Type.equal?(ChFloat32, 3.14, 2.71)
      refute Ash.Type.equal?(ChFloat64, 2.718, 1.618)
      refute Ash.Type.equal?(ChFloat32, 3.14, nil)
      refute Ash.Type.equal?(ChFloat64, nil, 2.718)
    end

    test "returns true for equal arrays of floats" do
      assert Ash.Type.equal?({:array, ChFloat32}, [3.14, 2.71], [3.14, 2.71])
      assert Ash.Type.equal?({:array, ChFloat64}, [1.618, 2.718], [1.618, 2.718])
      assert Ash.Type.equal?({:array, ChFloat32}, [], [])
    end

    test "returns false for different arrays of floats" do
      refute Ash.Type.equal?({:array, ChFloat32}, [3.14, 2.71], [2.71, 3.14])
      refute Ash.Type.equal?({:array, ChFloat64}, [1.618], [1.618, 2.718])
      refute Ash.Type.equal?({:array, ChFloat32}, [3.14, nil], [3.14, 2.71])
    end
  end

  describe "simple_equality?/0" do
    test "returns true for ChFloat32 and ChFloat64" do
      assert Ash.Type.simple_equality?(ChFloat32)
      assert Ash.Type.simple_equality?(ChFloat64)
    end

    test "returns true for array versions" do
      assert Ash.Type.simple_equality?({:array, ChFloat32})
      assert Ash.Type.simple_equality?({:array, ChFloat64})
    end
  end
end
