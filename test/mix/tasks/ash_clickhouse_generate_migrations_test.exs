defmodule Mix.Tasks.AshClickhouse.GenerateMigrationsTest do
  use ExUnit.Case, async: false

  alias AshClickhouse.Mix.Helpers
  alias AshClickhouse.TestRepo

  @domain "AshClickhouse.Test.Migration.Domain"

  setup do
    tmp = Path.join(System.tmp_dir!(), "codegen_test_#{System.unique_integer([:positive])}")
    shell = Mix.shell()

    Mix.shell(Mix.Shell.Quiet)
    File.mkdir_p!(Path.join(tmp, "migrations"))
    File.mkdir_p!(Path.join(tmp, "snapshots"))

    on_exit(fn ->
      Mix.shell(shell)
      File.rm_rf!(tmp)
    end)

    {:ok, migrations: Path.join(tmp, "migrations"), snapshots: Path.join(tmp, "snapshots")}
  end

  defp run(argv, ctx) do
    Mix.Tasks.AshClickhouse.GenerateMigrations.run(
      argv ++
        [
          "--domains",
          @domain,
          "--migrations-path",
          ctx.migrations,
          "--snapshot-path",
          ctx.snapshots
        ]
    )
  end

  defp files(dir), do: dir |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()

  defp migrations(ctx), do: files(Path.join(ctx.migrations, "*.exs"))

  defp snapshots(ctx), do: files(Path.join(ctx.snapshots, "*.json"))

  defp generated_sql(ctx) do
    Path.join(ctx.migrations, "*.exs") |> Path.wildcard() |> Enum.map_join("\n", &File.read!/1)
  end

  defp write_snapshot!(ctx, table, domain) do
    File.write!(
      Path.join(ctx.snapshots, "#{table}.json"),
      Jason.encode!(%{
        "table" => table,
        "domain" => domain,
        "engine" => "MergeTree()",
        "options" => "order by id",
        "columns" => [%{"name" => "id", "type" => "UUID"}]
      })
    )
  end

  test "a named run writes one migration and a snapshot per migrated table", ctx do
    run(["--name", "initial"], ctx)

    assert ["events.json"] = snapshots(ctx)
    assert [migration] = migrations(ctx)
    assert migration =~ ~r/^\d{14}_initial\.exs$/

    sql = generated_sql(ctx)
    assert sql =~ "CREATE TABLE events"
    assert sql =~ "DROP TABLE events"
  end

  test "a resource with migrate? false gets neither DDL nor a snapshot", ctx do
    run(["--name", "initial"], ctx)

    refute "ignoreds.json" in snapshots(ctx)
    refute generated_sql(ctx) =~ "ignoreds"
  end

  test "a second run with nothing changed generates no migration", ctx do
    run(["--name", "initial"], ctx)
    run(["--name", "again"], ctx)

    assert [_only_one] = migrations(ctx)
  end

  test "--check writes nothing and raises while a migration is outstanding", ctx do
    assert_raise Ash.Error.Framework.PendingCodegen, fn -> run(["--check"], ctx) end

    assert [] = migrations(ctx)
    assert [] = snapshots(ctx)

    run(["--name", "initial"], ctx)

    assert :ok = run(["--check"], ctx)
  end

  test "--dry-run writes nothing", ctx do
    run(["--dry-run"], ctx)

    assert [] = migrations(ctx)
    assert [] = snapshots(ctx)
  end

  test "--dev prefixes the name and records snapshots, so it cannot repeat itself", ctx do
    run(["--dev"], ctx)

    assert [first] = migrations(ctx)
    assert first =~ ~r/^\d{14}_dev_migrate_resources\.exs$/
    assert ["events.json"] = snapshots(ctx)

    run(["--dev"], ctx)

    assert [^first] = migrations(ctx)
  end

  test "a version already claimed under another name is skipped", ctx do
    taken = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    File.write!(Path.join(ctx.migrations, "#{taken}_hand_written.exs"), "")

    run(["--name", "initial"], ctx)

    assert [generated] = files(Path.join(ctx.migrations, "*_initial.exs"))
    refute String.starts_with?(generated, taken)
  end

  test "the module name is suffixed with its own migration's version", ctx do
    run(["--name", "initial"], ctx)

    assert [migration] = migrations(ctx)
    [version, _] = String.split(migration, "_", parts: 2)

    assert generated_sql(ctx) =~ "defmodule AshClickhouse.TestRepo.Migrations.Initial#{version}"
  end

  test "a snapshot owned by a domain outside the run is left alone", ctx do
    write_snapshot!(ctx, "orphan", "Elixir.Some.Other.Domain")

    run(["--name", "initial"], ctx)

    refute generated_sql(ctx) =~ "orphan"
    assert "orphan.json" in snapshots(ctx)
  end

  test "a snapshot claimed by a migrate? false resource is left alone", ctx do
    write_snapshot!(ctx, "ignoreds", "Elixir.AshClickhouse.Test.Migration.Domain")

    run(["--name", "initial"], ctx)

    refute generated_sql(ctx) =~ "DROP TABLE ignoreds"
    assert "ignoreds.json" in snapshots(ctx)
  end

  test "a snapshot the run owns and no resource claims survives without --drop-tables", ctx do
    write_snapshot!(ctx, "gone", "Elixir.AshClickhouse.Test.Migration.Domain")

    run(["--name", "initial"], ctx)

    refute generated_sql(ctx) =~ "DROP TABLE gone"
    assert "gone.json" in snapshots(ctx)
  end

  test "--drop-tables drops a snapshot the run owns and no resource claims", ctx do
    write_snapshot!(ctx, "gone", "Elixir.AshClickhouse.Test.Migration.Domain")

    run(["--name", "initial", "--drop-tables"], ctx)

    assert generated_sql(ctx) =~ "DROP TABLE gone"
    refute "gone.json" in snapshots(ctx)
  end

  test "--drop-tables still spares a snapshot owned by a domain outside the run", ctx do
    write_snapshot!(ctx, "orphan", "Elixir.Some.Other.Domain")

    run(["--name", "initial", "--drop-tables"], ctx)

    refute generated_sql(ctx) =~ "orphan"
    assert "orphan.json" in snapshots(ctx)
  end

  test "--check refuses while a --dev migration still carries its placeholder name", ctx do
    run(["--dev"], ctx)

    assert_raise Mix.Error, ~r/placeholder\s+name/, fn -> run(["--check"], ctx) end
  end

  test "a change that needs no DDL still refreshes the snapshot", ctx do
    run(["--name", "initial"], ctx)

    stale =
      Path.join(ctx.snapshots, "events.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("domain", "Elixir.Some.Older.Domain")

    File.write!(Path.join(ctx.snapshots, "events.json"), Jason.encode!(stale))

    run(["--name", "again"], ctx)

    assert [_only_one] = migrations(ctx)

    assert %{"domain" => "Elixir.AshClickhouse.Test.Migration.Domain"} =
             Path.join(ctx.snapshots, "events.json") |> File.read!() |> Jason.decode!()
  end

  test "a repo whose resources all opt out is still asked about its orphans", ctx do
    write_snapshot!(ctx, "gone", "Elixir.AshClickhouse.Test.Unmigrated.Domain")

    Mix.Tasks.AshClickhouse.GenerateMigrations.run([
      "--name",
      "initial",
      "--drop-tables",
      "--domains",
      "AshClickhouse.Test.Unmigrated.Domain",
      "--migrations-path",
      ctx.migrations,
      "--snapshot-path",
      ctx.snapshots
    ])

    assert generated_sql(ctx) =~ "DROP TABLE gone"
    refute "gone.json" in snapshots(ctx)
  end

  test "snapshots are not written to the repo's own directory when redirected", ctx do
    run(["--name", "initial"], ctx)

    refute File.exists?(Path.join(Helpers.source_repo_priv(TestRepo), "snapshots"))
  end
end
