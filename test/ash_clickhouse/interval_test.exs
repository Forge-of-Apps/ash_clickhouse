defmodule AshClickhouse.IntervalTest do
  use AshClickhouse.RepoCase, async: true

  alias AshClickhouse.Test.Resource.Visit

  require Ash.Expr
  require Ash.Query

  @instants [~U[2026-01-30 23:30:00Z], ~U[2024-02-29 23:30:00Z], ~U[2026-03-28 23:30:00Z]]

  @durations [
    Duration.new!(year: 1, month: 1),
    Duration.new!(year: -1),
    Duration.new!(month: 1, day: -1),
    Duration.new!(week: 2),
    Duration.new!(day: 0),
    Duration.new!(week: 1, hour: 25, minute: -90),
    Duration.new!(month: -1, second: 30, microsecond: {250, 6})
  ]

  setup do
    TestRepo.query!("TRUNCATE TABLE visits")
    :ok
  end

  defp visit!(page, at, stay_days \\ 0) do
    at = DateTime.truncate(at, :second)

    Visit
    |> Ash.Changeset.for_create(:create, %{
      page: page,
      at: at,
      local_at: at,
      stay_days: stay_days,
      on: DateTime.to_date(at)
    })
    |> Ash.create!()
  end

  defp pages(query), do: query |> Ash.read!() |> Enum.map(& &1.page) |> Enum.sort()

  defp assert_lands(expression, expected) do
    assert {expression, ["visit"]} ==
             {expression, Visit |> Ash.Query.filter(^expression == ^expected) |> pages()}
  end

  defp shift(%Date{} = date, duration),
    do: date |> DateTime.new!(~T[00:00:00]) |> DateTime.shift(duration) |> DateTime.to_date()

  defp shift(datetime, duration), do: DateTime.shift(datetime, duration)

  defp duration(:millisecond, amount), do: Duration.new!(microsecond: {amount * 1000, 3})
  defp duration(:microsecond, amount), do: Duration.new!(microsecond: {amount, 6})
  defp duration(unit, amount), do: Duration.new!([{unit, amount}])

  test "a read action filters by ago/2" do
    now = DateTime.utc_now()
    visit!("old", DateTime.add(now, -31, :day))
    visit!("new", DateTime.add(now, -29, :day))

    assert ["new"] = Visit |> Ash.Query.for_read(:recent) |> pages()
  end

  test "ago/2 takes its amount from an argument" do
    now = DateTime.utc_now()
    visit!("old", DateTime.add(now, -8, :day))
    visit!("new", DateTime.add(now, -6, :day))

    assert ["new"] = Visit |> Ash.Query.for_read(:since, %{days: 7}) |> pages()
    assert ["new", "old"] = Visit |> Ash.Query.for_read(:since, %{days: 9}) |> pages()
  end

  test "ago/1 takes a Duration, from an argument too" do
    now = DateTime.utc_now()
    visit!("old", DateTime.add(now, -31, :day))
    visit!("new", DateTime.add(now, -29, :day))

    assert ["new"] = Visit |> Ash.Query.filter(at > ago(^Duration.new!(day: 30))) |> pages()
    assert ["new"] = Visit |> Ash.Query.for_read(:within, %{window: "P30D"}) |> pages()

    assert ["new", "old"] =
             Visit |> Ash.Query.for_read(:within, %{window: Duration.new!(month: 2)}) |> pages()
  end

  test "from_now/2 and from_now/1 shift the current time forward" do
    now = DateTime.utc_now()
    visit!("soon", DateTime.add(now, 30, :minute))
    visit!("later", DateTime.add(now, 2, :hour))

    assert ["soon"] = Visit |> Ash.Query.filter(at < from_now(1, :hour)) |> pages()

    assert ["soon"] =
             Visit |> Ash.Query.filter(at < from_now(^Duration.new!(hour: 1))) |> pages()
  end

  test "datetime_add/3 takes its amount from a column" do
    now = DateTime.utc_now()
    visit!("staying", DateTime.add(now, -10, :day), 15)
    visit!("gone", DateTime.add(now, -10, :day), 5)

    assert ["staying"] =
             Visit |> Ash.Query.filter(datetime_add(at, stay_days, :day) > now()) |> pages()
  end

  test "shifting by a unit lands where a Postgres interval lands" do
    for instant <- @instants do
      TestRepo.query!("TRUNCATE TABLE visits")
      visit!("visit", instant)
      date = DateTime.to_date(instant)

      for unit <- Ash.Type.DurationName.values(), amount <- [1, -1] do
        duration = duration(unit, amount)
        assert_lands(Ash.Expr.expr(datetime_add(at, ^amount, ^unit)), shift(instant, duration))

        assert_lands(
          Ash.Expr.expr(datetime_add(local_at, ^amount, ^unit)),
          shift(instant, duration)
        )

        assert_lands(Ash.Expr.expr(date_add(on, ^amount, ^unit)), shift(date, duration))
      end
    end
  end

  test "shifting by a Duration lands where a Postgres interval lands" do
    for instant <- @instants do
      TestRepo.query!("TRUNCATE TABLE visits")
      visit!("visit", instant)
      date = DateTime.to_date(instant)

      for duration <- @durations do
        assert_lands(Ash.Expr.expr(datetime_add(at, ^duration)), shift(instant, duration))
        assert_lands(Ash.Expr.expr(datetime_add(local_at, ^duration)), shift(instant, duration))
        assert_lands(Ash.Expr.expr(date_add(on, ^duration)), shift(date, duration))
      end
    end
  end

  test "ago and from_now count from a read's as_of" do
    as_of = ~U[2026-01-15 12:00:00Z]
    visit!("short", ~U[2026-01-10 12:00:00Z], 3)
    visit!("long", ~U[2026-01-10 12:00:00Z], 7)
    visit!("later", ~U[2026-03-01 12:00:00Z])

    assert ["later", "long"] =
             Visit
             |> Ash.Query.filter(at > ago(stay_days, :day))
             |> Ash.Query.as_of(as_of)
             |> pages()

    assert ["long", "short"] =
             Visit
             |> Ash.Query.filter(at < from_now(^Duration.new!(day: 1)))
             |> Ash.Query.as_of(as_of)
             |> pages()
  end

  test "the session's time zone does not move a shift" do
    visit!("visit", ~U[2026-01-30 23:30:00Z])

    {:ok, query} =
      Visit
      |> Ash.Query.filter(
        datetime_add(^~U[2026-01-30 23:30:00Z], 1, :month) == ^~U[2026-02-28 23:30:00Z]
      )
      |> Ash.Query.data_layer_query()

    assert [%{page: "visit"}] = TestRepo.all(query, settings: [session_timezone: "Europe/Berlin"])
  end

  test "a nil argument shifts to nil" do
    visit!("visit", ~U[2026-01-30 23:30:00Z])

    assert ["visit"] =
             Visit |> Ash.Query.filter(is_nil(datetime_add(at, ^nil, :day))) |> pages()

    assert ["visit"] = Visit |> Ash.Query.filter(is_nil(date_add(on, ^nil))) |> pages()
    assert ["visit"] = Visit |> Ash.Query.filter(is_nil(ago(^nil))) |> pages()
  end

  test "a Duration or unit only known in the database is refused" do
    visit!("visit", ~U[2026-01-30 23:30:00Z])

    assert_raise Ash.Error.Unknown, ~r/ClickHouse has no value for a Duration/, fn ->
      Visit
      |> Ash.Query.filter(
        at > ago(if(stay_days > 1, ^Duration.new!(day: 1), ^Duration.new!(day: 2)))
      )
      |> pages()
    end

    assert_raise Ash.Error.Unknown, ~r/ClickHouse names the unit of an interval/, fn ->
      Visit |> Ash.Query.filter(at > ago(1, if(stay_days > 1, :day, :hour))) |> pages()
    end
  end
end
