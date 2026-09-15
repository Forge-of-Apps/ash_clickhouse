defmodule AshClickhouse.DataLayer.Info do
  @moduledoc "Introspection functions for Clickhouse"

  alias Spark.Dsl.Extension

  @doc "The configured repo for a resource"
  def repo(resource, type \\ :mutate) do
    case Extension.get_opt(resource, [:clickhouse], :repo, nil, true) do
      fun when is_function(fun, 2) ->
        fun.(resource, type)

      repo ->
        repo
    end
  end

  @doc """
  The materialized view a resource declares, or `nil` when it is a plain table.

  Shaped for the migration generator and its snapshots: `%{"source" => ...,
  "to" => ... | nil, "select" => ...}`, with the SELECT already rendered, so a
  snapshot records the SQL that reached ClickHouse rather than the query that
  produced it.
  """
  def materialized_view(resource) do
    case Extension.get_opt(resource, [:clickhouse, :materialized_view], :source, nil, true) do
      nil ->
        nil

      source ->
        source = table_name(source)
        to = resource |> view_opt(:to) |> table_name()

        {select, aliases} =
          AshClickhouse.MaterializedView.select_sql(
            source,
            view_opt(resource, :query),
            view_opt(resource, :select)
          )

        if to do
          AshClickhouse.MaterializedView.validate_aliases!(
            table(resource),
            aliases,
            destination_columns(resource, to)
          )
        end

        %{"source" => source, "to" => to, "select" => select}
    end
  end

  defp view_opt(resource, key) do
    Extension.get_opt(resource, [:clickhouse, :materialized_view], key, nil, true)
  end

  defp table_name(nil), do: nil
  defp table_name(table) when is_binary(table), do: table
  defp table_name(resource) when is_atom(resource), do: table(resource)

  defp destination_columns(resource, to) do
    resource
    |> Ash.Resource.Info.domain()
    |> Ash.Domain.Info.resources()
    |> Enum.find(&(Ash.DataLayer.data_layer(&1) == AshClickhouse.DataLayer and table(&1) == to))
    |> case do
      nil ->
        raise """
        #{table(resource)} writes into #{to}, which no resource in         #{inspect(Ash.Resource.Info.domain(resource))} declares.

        Give the destination table a resource in the same domain, so the view's         columns can be checked against it and the table itself gets migrated.
        """

      destination ->
        destination |> Ash.Resource.Info.attributes() |> Enum.map(&to_string(&1.name))
    end
  end

  def engine(resource) do
    Extension.get_opt(resource, [:clickhouse], :engine, nil, true)
  end

  def options(resource) do
    Extension.get_opt(resource, [:clickhouse], :options, [], true)
  end

  @doc "A keyword list of calculations to their sql representation"
  def calculations_to_sql(resource) do
    Extension.get_opt(resource, [:clickhouse], :calculations_to_sql, [])
  end

  def calculation_to_sql(resource, calc) do
    calculations_to_sql(resource)[calc]
  end

  @doc """
  A keyword list of identity names to the literal SQL string representation of
  the `where` clause portion of identity's partial unique index.

  For example, given the following identity for a resource:

      identities do
        identity :active, [:status] do
          where expr(status == "active")
        end
      end
  """
  @spec identity_wheres_to_sql(Ash.Resource.t()) :: keyword(String.t())
  def identity_wheres_to_sql(resource) do
    Extension.get_opt(resource, [:clickhouse], :identity_wheres_to_sql, [])
  end

  @doc """
  Returns the literal SQL for the `where` clause given a resource and an
  identity name.

  See `identity_wheres_to_sql/1` for more details.
  """
  @spec identity_where_to_sql(Ash.Resource.t(), atom()) :: String.t() | nil
  def identity_where_to_sql(resource, identity) do
    identity_wheres_to_sql(resource)[identity]
  end

  @doc "The configured table for a resource"
  def table(resource) do
    Extension.get_opt(resource, [:clickhouse], :table, nil, true)
  end

  def simple_join_first_aggregates(resource) do
    Extension.get_opt(resource, [:clickhouse], :simple_join_first_aggregates, [])
  end

  @doc "The configured schema for a resource"
  def schema(resource) do
    Extension.get_opt(resource, [:clickhouse], :schema, nil, true)
  end

  @doc "The configured references for a resource"
  def references(resource) do
    Extension.get_entities(resource, [:clickhouse, :references])
  end

  @doc "The configured reference for a given relationship of a  resource"
  def reference(resource, relationship) do
    resource
    |> Extension.get_entities([:clickhouse, :references])
    |> Enum.find(&(&1.relationship == relationship))
  end

  @doc "A keyword list of customized migration types"
  def migration_types(resource) do
    Extension.get_opt(resource, [:clickhouse], :migration_types, [])
  end

  @doc "A keyword list of customized storage types"
  def storage_types(resource) do
    Extension.get_opt(resource, [:clickhouse], :storage_types, [])
  end

  @doc "A keyword list of customized migration defaults"
  def migration_defaults(resource) do
    Extension.get_opt(resource, [:clickhouse], :migration_defaults, [])
  end

  @doc "A list of attributes to be ignored when generating migrations"
  def migration_ignore_attributes(resource) do
    Extension.get_opt(resource, [:clickhouse], :migration_ignore_attributes, [])
  end

  @doc "The configured check_constraints for a resource"
  def check_constraints(resource) do
    Extension.get_entities(resource, [:clickhouse, :check_constraints])
  end

  @doc "The configured custom_indexes for a resource"
  def custom_indexes(resource) do
    Extension.get_entities(resource, [:clickhouse, :custom_indexes])
  end

  @doc "The configured custom_statements for a resource"
  def custom_statements(resource) do
    Extension.get_entities(resource, [:clickhouse, :custom_statements])
  end

  @doc "The configured polymorphic_reference_on_delete for a resource"
  def polymorphic_on_delete(resource) do
    Extension.get_opt(resource, [:clickhouse, :references], :polymorphic_on_delete, nil, true)
  end

  @doc "The configured polymorphic_reference_on_update for a resource"
  def polymorphic_on_update(resource) do
    Extension.get_opt(resource, [:clickhouse, :references], :polymorphic_on_update, nil, true)
  end

  @doc "The configured polymorphic_reference_name for a resource"
  def polymorphic_name(resource) do
    Extension.get_opt(resource, [:clickhouse, :references], :polymorphic_name, nil, true)
  end

  @doc "The configured polymorphic? for a resource"
  def polymorphic?(resource) do
    Extension.get_opt(resource, [:clickhouse], :polymorphic?, nil, true)
  end

  @doc "The configured unique_index_names"
  def unique_index_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :unique_index_names, [], true)
  end

  @doc "The configured exclusion_constraint_names"
  def exclusion_constraint_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :exclusion_constraint_names, [], true)
  end

  @doc "The configured identity_index_names"
  def identity_index_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :identity_index_names, [], true)
  end

  @doc "Identities not to include in the migrations"
  def skip_identities(resource) do
    Extension.get_opt(resource, [:clickhouse], :skip_identities, [], true)
  end

  @doc "The configured foreign_key_names"
  def foreign_key_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :foreign_key_names, [], true)
  end

  @doc "Whether or not the resource should be included when generating migrations"
  def migrate?(resource) do
    Extension.get_opt(resource, [:clickhouse], :migrate?, nil, true)
  end

  @doc "A list of keys to always include in upserts."
  def global_upsert_keys(resource) do
    Extension.get_opt(resource, [:clickhouse], :global_upsert_keys, [])
  end

  @doc "A stringified version of the base_filter, to be used in a where clause when generating unique indexes"
  def base_filter_sql(resource) do
    Extension.get_opt(resource, [:clickhouse], :base_filter_sql, nil)
  end

  @doc "Skip generating unique indexes when generating migrations"
  def skip_unique_indexes(resource) do
    Extension.get_opt(resource, [:clickhouse], :skip_unique_indexes, [])
  end

  @doc "The template for a managed tenant"
  def manage_tenant_template(resource) do
    Extension.get_opt(resource, [:clickhouse, :manage_tenant], :template, nil)
  end

  @doc "Whether or not to create a tenant for a given resource"
  def manage_tenant_create?(resource) do
    Extension.get_opt(resource, [:clickhouse, :manage_tenant], :create?, false)
  end

  @doc "Whether or not to update a tenant for a given resource"
  def manage_tenant_update?(resource) do
    Extension.get_opt(resource, [:clickhouse, :manage_tenant], :update?, false)
  end
end
