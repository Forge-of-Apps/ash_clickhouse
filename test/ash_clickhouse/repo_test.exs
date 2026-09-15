defmodule AshClickhouse.RepoTest do
  use ExUnit.Case, async: true

  test "starting a repo settles ecto_ch's default table engine" do
    assert Application.get_env(:ecto_ch, :default_table_engine) == "MergeTree"
  end
end
