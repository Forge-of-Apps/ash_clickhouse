defmodule Mix.Tasks.AshClickhouse.GenerateMigrationsTest do
  @moduledoc """
  The migrations are generated into a temporary directory, but they are applied
  to the one test repo, so a version left in `schema_migrations` outlives the
  test that wrote it. Timestamps are second-granular and the suite is faster
  than that, so the next test's migration can be handed a version already
  recorded as applied; the teardown takes each one back out.
  """

  use ExUnit.Case, async: false

  @domain "AshClickhouse.Test.Migration.Domain"

  setup do
    tmp = Path.join(System.tmp_dir!(), "codegen_test_#{System.unique_integer([:positive])}")
    shell = Mix.shell()

    Mix.shell(Mix.Shell.Quiet)
    File.mkdir_p!(Path.join(tmp, "migrations"))
    File.mkdir_p!(Path.join(tmp, "snapshots"))

    on_exit(fn ->
      Mix.shell(shell)

      tmp
      |> Path.join("migrations/*.exs")
      |> Path.wildcard()
      |> Enum.map(&(&1 |> Path.basename() |> String.split("_", parts: 2) |> hd()))
      |> Enum.each(fn version ->
        AshClickhouse.TestRepo.query!(
          "ALTER TABLE schema_migrations DELETE WHERE version = #{version} SETTINGS mutations_sync = 1"
        )
      end)

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
          "--migration-path",
          ctx.migrations,
          "--snapshot-path",
          ctx.snapshots
        ]
    )
  end

  defp migrations(ctx) do
    ctx.migrations |> Path.join("*.exs") |> Path.wildcard() |> Enum.map(&Path.basename/1)
  end

  defp snapshot_tables(ctx) do
    ctx.snapshots
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp snapshots(ctx, table) do
    ctx.snapshots
    |> Path.join("#{table}/*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp generated_sql(ctx) do
    ctx.migrations |> Path.join("*.exs") |> Path.wildcard() |> Enum.map_join("\n", &File.read!/1)
  end

  defp write_snapshot!(ctx, table, domain) do
    dir = Path.join(ctx.snapshots, table)
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "20200101000000.json"),
      Jason.encode!(%{
        "table" => table,
        "domain" => domain,
        "engine" => "MergeTree()",
        "options" => "order by id",
        "columns" => [%{"name" => "id", "type" => "UUID"}]
      })
    )
  end

  describe "naming" do
    test "the first argument names the migration and its module", ctx do
      run(["add_events"], ctx)

      assert [migration] = migrations(ctx)
      assert migration =~ ~r/^\d{14}_add_events\.exs$/
      assert generated_sql(ctx) =~ "defmodule AshClickhouse.TestRepo.Migrations.AddEvents do"
    end

    test "--name does the same as the first argument", ctx do
      run(["--name", "add_events"], ctx)

      assert [migration] = migrations(ctx)
      assert migration =~ ~r/^\d{14}_add_events\.exs$/
    end

    test "the nil name `mix ash.codegen` passes when it has none is tolerated", ctx do
      assert :ok = run(["--dev", "--name", nil], ctx)

      assert [migration] = migrations(ctx)
      assert migration =~ ~r/^\d{14}_migrate_resources1_dev\.exs$/
    end

    test "a run with no name and nothing to excuse it is refused", ctx do
      assert_raise RuntimeError, ~r/Name must be provided/, fn -> run([], ctx) end

      assert [] = migrations(ctx)
    end

    test "--auto-name falls back to a numbered name", ctx do
      run(["--auto-name"], ctx)

      assert [migration] = migrations(ctx)
      assert migration =~ ~r/^\d{14}_migrate_resources1\.exs$/
      assert generated_sql(ctx) =~ "Migrations.MigrateResources1 do"
    end

    test "--auto-name counts up from the migrations already there", ctx do
      File.write!(Path.join(ctx.migrations, "20200101000001_migrate_resources7.exs"), "")

      run(["--auto-name"], ctx)

      assert Enum.any?(migrations(ctx), &(&1 =~ "migrate_resources8"))
    end
  end

  describe "--dev" do
    test "writes a _dev migration and a _dev snapshot", ctx do
      run(["--dev"], ctx)

      assert [migration] = migrations(ctx)
      assert migration =~ ~r/^\d{14}_migrate_resources1_dev\.exs$/

      assert ["events"] = snapshot_tables(ctx)
      assert [snapshot] = snapshots(ctx, "events")
      assert snapshot =~ ~r/^\d{14}_dev\.json$/
    end

    test "a second --dev run with nothing changed adds nothing", ctx do
      run(["--dev"], ctx)
      run(["--dev"], ctx)

      assert [_only_one] = migrations(ctx)
    end

    test "a named run replaces the dev migration and its snapshot", ctx do
      run(["--dev"], ctx)

      assert [dev] = migrations(ctx)
      assert dev =~ "_dev.exs"

      run(["add_events"], ctx)

      assert [migration] = migrations(ctx)
      assert migration =~ ~r/^\d{14}_add_events\.exs$/

      assert [snapshot] = snapshots(ctx, "events")
      refute snapshot =~ "_dev"
    end

    test "a dev migration that was applied is rolled back before it is replaced", ctx do
      repo = AshClickhouse.TestRepo

      tables =
        AshClickhouse.Test.Migration.Domain
        |> Ash.Domain.Info.resources()
        |> Enum.map(&AshClickhouse.DataLayer.Info.table/1)

      on_exit(fn ->
        Enum.each(tables, &repo.query!("DROP TABLE IF EXISTS #{&1}"))
      end)

      run(["--dev"], ctx)
      Ecto.Migrator.run(repo, ctx.migrations, :up, all: true, log: false)

      assert %{rows: [[1]]} = repo.query!("EXISTS TABLE events")

      run(["add_events"], ctx)

      assert %{rows: [[0]]} = repo.query!("EXISTS TABLE events")
      assert [migration] = migrations(ctx)
      assert migration =~ "_add_events.exs"

      Ecto.Migrator.run(repo, ctx.migrations, :up, all: true, log: false)
      assert %{rows: [[1]]} = repo.query!("EXISTS TABLE events")
    end

    test "--check refuses while a dev migration is still there", ctx do
      run(["--dev"], ctx)

      assert_raise Mix.Error, ~r/generated with the --dev flag/, fn -> run(["--check"], ctx) end
    end
  end

  describe "writing" do
    test "a named run writes one migration and a snapshot per migrated table", ctx do
      run(["initial"], ctx)

      assert ["events"] = snapshot_tables(ctx)
      assert [_snapshot] = snapshots(ctx, "events")

      sql = generated_sql(ctx)
      assert sql =~ "CREATE TABLE events"
      assert sql =~ "DROP TABLE events"
    end

    test "the migration is formatted", ctx do
      run(["initial"], ctx)

      contents = generated_sql(ctx)

      assert contents == IO.iodata_to_binary([Code.format_string!(contents), "\n"])
    end

    test "a resource with migrate? false gets neither DDL nor a snapshot", ctx do
      run(["initial"], ctx)

      refute "ignoreds" in snapshot_tables(ctx)
      refute generated_sql(ctx) =~ "ignoreds"
    end

    test "a second run with nothing changed generates nothing", ctx do
      run(["initial"], ctx)
      run(["again"], ctx)

      assert [_only_one] = migrations(ctx)
      assert [_only_one] = snapshots(ctx, "events")
    end

    test "--snapshots-only writes the snapshot without a migration", ctx do
      run(["initial", "--snapshots-only"], ctx)

      assert [] = migrations(ctx)
      assert [_snapshot] = snapshots(ctx, "events")
    end

    test "--dry-run writes nothing", ctx do
      run(["--dry-run"], ctx)

      assert [] = migrations(ctx)
      assert [] = snapshot_tables(ctx)
    end

    test "--check writes nothing and raises while a migration is outstanding", ctx do
      assert_raise Ash.Error.Framework.PendingCodegen, fn -> run(["--check"], ctx) end

      assert [] = migrations(ctx)
      assert [] = snapshot_tables(ctx)

      run(["initial"], ctx)

      assert :ok = run(["--check"], ctx)
    end

    test "a change that needs no DDL still records a snapshot", ctx do
      run(["initial"], ctx)

      assert [existing] = snapshots(ctx, "events")

      stale =
        [ctx.snapshots, "events", existing]
        |> Path.join()
        |> File.read!()
        |> Jason.decode!()
        |> Map.put("domain", "Elixir.Some.Older.Domain")

      File.write!(Path.join([ctx.snapshots, "events", existing]), Jason.encode!(stale))

      run(["again"], ctx)

      assert [_only_one] = migrations(ctx)

      assert %{"domain" => "Elixir.AshClickhouse.Test.Migration.Domain"} =
               ctx.snapshots
               |> Path.join("events/*.json")
               |> Path.wildcard()
               |> Enum.max()
               |> File.read!()
               |> Jason.decode!()
    end
  end

  describe "orphans" do
    test "a snapshot owned by a domain outside the run is left alone", ctx do
      write_snapshot!(ctx, "orphan", "Elixir.Some.Other.Domain")

      run(["initial"], ctx)

      refute generated_sql(ctx) =~ "orphan"
      assert "orphan" in snapshot_tables(ctx)
    end

    test "a snapshot claimed by a migrate? false resource is left alone", ctx do
      write_snapshot!(ctx, "ignoreds", "Elixir.AshClickhouse.Test.Migration.Domain")

      run(["initial"], ctx)

      refute generated_sql(ctx) =~ "DROP TABLE ignoreds"
      assert "ignoreds" in snapshot_tables(ctx)
    end

    test "a snapshot the run owns and no resource claims survives without --drop-tables", ctx do
      write_snapshot!(ctx, "gone", "Elixir.AshClickhouse.Test.Migration.Domain")

      run(["initial"], ctx)

      refute generated_sql(ctx) =~ "DROP TABLE gone"
      assert "gone" in snapshot_tables(ctx)
    end

    test "--drop-tables drops a snapshot the run owns and no resource claims", ctx do
      write_snapshot!(ctx, "gone", "Elixir.AshClickhouse.Test.Migration.Domain")

      run(["initial", "--drop-tables"], ctx)

      assert generated_sql(ctx) =~ "DROP TABLE gone"
      refute "gone" in snapshot_tables(ctx)
    end

    test "--drop-tables still spares a snapshot owned by a domain outside the run", ctx do
      write_snapshot!(ctx, "orphan", "Elixir.Some.Other.Domain")

      run(["initial", "--drop-tables"], ctx)

      refute generated_sql(ctx) =~ "orphan"
      assert "orphan" in snapshot_tables(ctx)
    end

    test "a repo whose resources all opt out is still asked about its orphans", ctx do
      write_snapshot!(ctx, "gone", "Elixir.AshClickhouse.Test.Unmigrated.Domain")

      Mix.Tasks.AshClickhouse.GenerateMigrations.run([
        "initial",
        "--drop-tables",
        "--domains",
        "AshClickhouse.Test.Unmigrated.Domain",
        "--migration-path",
        ctx.migrations,
        "--snapshot-path",
        ctx.snapshots
      ])

      assert generated_sql(ctx) =~ "DROP TABLE gone"
      refute "gone" in snapshot_tables(ctx)
    end
  end
end
