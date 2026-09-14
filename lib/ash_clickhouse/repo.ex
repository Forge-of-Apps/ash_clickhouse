defmodule AshClickhouse.Repo do
  @moduledoc """
  Resources that use `AshClickhouse.DataLayer` use a `Repo` to access the database.

  This repo is a thin wrapper around an `Ecto.Repo`.

  You can use `Ecto.Repo`'s `init/2` to configure your repo like normal, but
  instead of returning `{:ok, config}`, use `super(config)` to pass the
  configuration to the `AshClickhouse.Repo` implementation.

  Starting a repo also settles `:ecto_ch`'s `default_table_engine` on
  `MergeTree`, unless the application has already chosen one. `ecto_ch` would
  otherwise default to `TinyLog`, which supports no `DELETE`: `Ecto.Migrator`
  runs a migration's `down` and then cannot remove its version row from
  `schema_migrations`, leaving the schema changed but still recorded as
  applied. Every table the migration generator writes names its own engine, so
  the default only ever reaches `schema_migrations` itself.

  This settles the engine for databases created from here on. One whose
  `schema_migrations` already exists keeps the engine it was made with, and a
  rollback against it still fails on removing the version row. Check with
  `SELECT engine FROM system.tables WHERE name = 'schema_migrations'`, and
  recreate the table if it says `TinyLog` — it holds nothing but applied
  versions, so `CREATE TABLE ... ENGINE = MergeTree ORDER BY version AS SELECT
  * FROM schema_migrations` under a new name, then swap them, loses nothing.
  """

  @doc "Use this to inform the data layer about what extensions are installed"
  @callback installed_extensions() :: [String.t()]

  @doc "The path where your migrations are stored"
  @callback migrations_path() :: String.t() | nil
  @doc "Allows overriding a given migration type for *all* fields, for example if you wanted to always use :timestamptz for :utc_datetime fields"
  @callback override_migration_type(atom) :: atom

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      otp_app = opts[:otp_app] || raise("Must configure OTP app")

      use Ecto.Repo,
        otp_app: otp_app,
        adapter: Ecto.Adapters.ClickHouse

      @behaviour AshClickhouse.Repo

      defoverridable insert: 2, insert: 1, insert!: 2, insert!: 1, all: 2

      def installed_extensions, do: []
      def migrations_path, do: nil
      def override_migration_type(type), do: type

      def create?, do: true
      def drop?, do: true

      def init(_, config) do
        if is_nil(Application.get_env(:ecto_ch, :default_table_engine)) do
          Application.put_env(:ecto_ch, :default_table_engine, "MergeTree")
        end

        new_config =
          config
          |> Keyword.put(:installed_extensions, installed_extensions())
          |> Keyword.put(:migrations_path, migrations_path())
          |> Keyword.put(:case_sensitive_like, :on)

        {:ok, new_config}
      end

      def insert(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> to_ecto()
        |> then(fn value ->
          repo = get_dynamic_repo()

          Ecto.Repo.Schema.insert(
            __MODULE__,
            repo,
            value,
            Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(:insert, opts))
          )
        end)
        |> from_ecto()
      end

      def insert!(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> to_ecto()
        |> then(fn value ->
          repo = get_dynamic_repo()

          Ecto.Repo.Schema.insert!(
            __MODULE__,
            repo,
            value,
            Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(:insert, opts))
          )
        end)
        |> from_ecto()
      end

      def from_ecto({:ok, result}), do: {:ok, from_ecto(result)}
      def from_ecto({:error, _} = other), do: other

      def from_ecto(nil), do: nil

      def from_ecto(value) when is_list(value) do
        Enum.map(value, &from_ecto/1)
      end

      def from_ecto(%resource{} = record) do
        if Spark.Dsl.is?(resource, Ash.Resource) do
          empty = struct(resource)

          resource
          |> Ash.Resource.Info.relationships()
          |> Enum.reduce(record, fn relationship, record ->
            case Map.get(record, relationship.name) do
              %Ecto.Association.NotLoaded{} ->
                Map.put(record, relationship.name, Map.get(empty, relationship.name))

              value ->
                Map.put(record, relationship.name, from_ecto(value))
            end
          end)
        else
          record
        end
      end

      def from_ecto(other), do: other

      def to_ecto(nil), do: nil

      def to_ecto(value) when is_list(value) do
        Enum.map(value, &to_ecto/1)
      end

      def to_ecto(%resource{} = record) do
        if Spark.Dsl.is?(resource, Ash.Resource) do
          resource
          |> Ash.Resource.Info.relationships()
          |> Enum.reduce(record, fn relationship, record ->
            value =
              case Map.get(record, relationship.name) do
                %Ash.NotLoaded{} ->
                  %Ecto.Association.NotLoaded{
                    __field__: relationship.name,
                    __cardinality__: relationship.cardinality
                  }

                value ->
                  to_ecto(value)
              end

            Map.put(record, relationship.name, value)
          end)
        else
          record
        end
      end

      def to_ecto(other), do: other

      def default_constraint_match_type(_constraint_type, _constraint_name) do
        :exact
      end

      defoverridable init: 2,
                     installed_extensions: 0,
                     override_migration_type: 1,
                     insert_all: 3,
                     default_constraint_match_type: 2
    end
  end
end
