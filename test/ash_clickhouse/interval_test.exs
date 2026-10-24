defmodule AshClickhouse.IntervalTest do
  use AshClickhouse.RepoCase, async: true

  alias Ash.Query.Function.Ago
  alias AshClickhouse.Test.Resource.Visit

  require Ash.Query

  setup do
    TestRepo.query!("TRUNCATE TABLE visits")
    :ok
  end

  defp visit!(page, at, stay_days \\ 0) do
    Visit
    |> Ash.Changeset.for_create(:create, %{
      page: page,
      at: DateTime.truncate(at, :second),
      stay_days: stay_days,
      on: DateTime.to_date(at)
    })
    |> Ash.create!()
  end

  defp pages(query), do: query |> Ash.read!() |> Enum.map(& &1.page) |> Enum.sort()

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

  test "from_now/2 shifts the current time forward" do
    now = DateTime.utc_now()
    visit!("soon", DateTime.add(now, 30, :minute))
    visit!("later", DateTime.add(now, 2, :hour))

    assert ["soon"] = Visit |> Ash.Query.filter(at < from_now(1, :hour)) |> pages()
  end

  test "datetime_add/3 takes its amount from a column" do
    now = DateTime.utc_now()
    visit!("staying", DateTime.add(now, -10, :day), 15)
    visit!("gone", DateTime.add(now, -10, :day), 5)

    assert ["staying"] =
             Visit |> Ash.Query.filter(datetime_add(at, stay_days, :day) > now()) |> pages()
  end

  test "datetime_add/3 shifts by every interval as Ash does" do
    at = ~U[2026-01-31 12:00:00Z]
    visit!("visit", at)

    for unit <- Ash.Type.DurationName.values() do
      expected = Ago.datetime_add(at, 3, unit)

      assert {unit, ["visit"]} ==
               {unit,
                Visit
                |> Ash.Query.filter(datetime_add(at, 3, ^unit) == ^expected)
                |> pages()}
    end
  end

  test "date_add/3 shifts a date and keeps it a date" do
    visit!("visit", ~U[2026-01-31 12:00:00Z])

    assert ["visit"] =
             Visit |> Ash.Query.filter(date_add(on, 1, :month) == ^~D[2026-02-28]) |> pages()

    assert ["visit"] =
             Visit |> Ash.Query.filter(date_add(on, 25, :hour) == ^~D[2026-02-01]) |> pages()
  end
end
