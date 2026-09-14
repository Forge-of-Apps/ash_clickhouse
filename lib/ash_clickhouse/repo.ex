defmodule AshClickhouse.Repo do
  @moduledoc """
  The repo a resource using `AshClickhouse.DataLayer` reads and writes through.

  A thin wrapper over an `Ecto.Repo` on the `Ecto.Adapters.ClickHouse` adapter:

      defmodule MyApp.ClickhouseRepo do
        use AshClickhouse.Repo, otp_app: :my_app
      end

  Configure it as any Ecto repo, and add it to `:ecto_repos` so
  `mix ash.setup` and `mix ash.migrate` find it:

      config :my_app, ecto_repos: [MyApp.Repo, MyApp.ClickhouseRepo]
      config :my_app, MyApp.ClickhouseRepo, url: System.get_env("CLICKHOUSE_URL")

  `Ecto.Repo`'s `init/2` can be overridden as usual; return `super(config)`
  rather than `{:ok, config}`, so this module's own configuration is applied
  too.

  ## `schema_migrations`

  Starting a repo settles `:ecto_ch`'s `default_table_engine` on `MergeTree`,
  unless the application has already chosen one. `ecto_ch` would otherwise
  default to `TinyLog`, which supports no `DELETE`: `Ecto.Migrator` runs a
  migration's `down` and then cannot remove its version row from
  `schema_migrations`, leaving the schema changed but still recorded as
  applied. Every table the migration generator writes names its own engine, so
  the default only ever reaches `schema_migrations` itself.
  """

  @doc """
  Where this repo's migrations live, overriding the derived
  `priv/<repo>/migrations`.

  `nil`, the default, keeps the derived path.
  """
  @callback migrations_path() :: String.t() | nil

  @doc false
  @callback installed_extensions() :: [String.t()]

  @doc false
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
