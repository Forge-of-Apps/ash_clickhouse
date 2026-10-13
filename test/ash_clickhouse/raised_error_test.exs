defmodule AshClickhouse.RaisedErrorTest do
  use AshClickhouse.RepoCase, async: true

  alias AshClickhouse.Test.Unmigrated.Thing

  test "a query ClickHouse rejects returns an error whose message can be formatted" do
    assert {:error, error} = Ash.read(Thing)

    message = Exception.message(error)

    refute message =~ "while retrieving Exception.message/1"
    assert message =~ ~r/^\* \*\* \(Ch\.Error\) .*UNKNOWN_TABLE/m
    assert message =~ "AshClickhouse.DataLayer.run_query/2"
  end
end
