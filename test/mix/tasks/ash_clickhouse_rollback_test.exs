defmodule AshClickhouse.RollbackTest do
  @moduledoc """
  `mix ash.rollback` reaches ClickHouse through
  `AshClickhouse.DataLayer.rollback/1`, which prompts for how far back to go
  and then runs `mix ash_clickhouse.rollback`.

  There is no way to point it at a throwaway directory — it reads the repo's
  own migrations path — so this writes one migration into it, rolls back only
  that one, and takes it away again.
  """

  use ExUnit.Case, async: false

  @version "29990101000000"

  setup do
    repo = AshClickhouse.TestRepo
    dir = AshClickhouse.Mix.Helpers.migrations_path([], repo)
    file = Path.join(dir, "#{@version}_rollback_probe.exs")
    shell = Mix.shell()

    File.write!(file, """
    defmodule AshClickhouse.TestRepo.Migrations.RollbackProbe do
      use Ecto.Migration

      def up,
        do: execute("CREATE TABLE rollback_probe (id UInt8) ENGINE = MergeTree() ORDER BY id")

      def down, do: execute("DROP TABLE rollback_probe")
    end
    """)

    on_exit(fn ->
      Mix.shell(shell)
      File.rm(file)
      repo.query!("DROP TABLE IF EXISTS rollback_probe")
      repo.query!("ALTER TABLE schema_migrations DELETE WHERE version = #{@version}")
    end)

    {:ok, repo: repo, dir: dir}
  end

  test "rolling back through the data layer undoes the newest migration", ctx do
    Ecto.Migrator.run(ctx.repo, ctx.dir, :up, all: true, log: false)

    assert %{rows: [[1]]} = ctx.repo.query!("EXISTS TABLE rollback_probe")

    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, "1"})

    AshClickhouse.DataLayer.rollback([])

    assert %{rows: [[0]]} = ctx.repo.query!("EXISTS TABLE rollback_probe")
  end
end
