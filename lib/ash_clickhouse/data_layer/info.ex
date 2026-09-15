defmodule AshClickhouse.DataLayer.Info do
  @moduledoc """
  Reads a resource's `clickhouse` block.

  The DSL is small, so this is too: `repo/2`, `table/1`, `engine/1`,
  `options/1`, `migrate?/1` and `materialized_view/1` are what a consumer
  needs. The rest read options inherited from `ash_postgres` that nothing in
  this data layer consults, so they answer with their defaults and nothing
  else; they are hidden from the docs for that reason.
  """

  alias Spark.Dsl.Extension

  @doc "The repo the resource reads from or writes to, resolved if it was given as a function."
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

  @doc "The table engine the resource declares, defaulting to `MergeTree()`."
  def engine(resource) do
    Extension.get_opt(resource, [:clickhouse], :engine, nil, true)
  end

  @doc """
  Everything following the engine in the resource's `CREATE TABLE`, as raw SQL.

  The sorting key above all. `[]` when the resource declares none.
  """
  def options(resource) do
    Extension.get_opt(resource, [:clickhouse], :options, [], true)
  end

  @doc false
  def calculations_to_sql(resource) do
    Extension.get_opt(resource, [:clickhouse], :calculations_to_sql, [])
  end

  @doc false
  def calculation_to_sql(resource, calc) do
    calculations_to_sql(resource)[calc]
  end

  @spec identity_wheres_to_sql(Ash.Resource.t()) :: keyword(String.t())
  @doc false
  def identity_wheres_to_sql(resource) do
    Extension.get_opt(resource, [:clickhouse], :identity_wheres_to_sql, [])
  end

  @spec identity_where_to_sql(Ash.Resource.t(), atom()) :: String.t() | nil
  @doc false
  def identity_where_to_sql(resource, identity) do
    identity_wheres_to_sql(resource)[identity]
  end

  @doc "The table the resource is stored in, or the name of the view for a materialized view."
  def table(resource) do
    Extension.get_opt(resource, [:clickhouse], :table, nil, true)
  end

  @doc false
  def simple_join_first_aggregates(resource) do
    Extension.get_opt(resource, [:clickhouse], :simple_join_first_aggregates, [])
  end

  @doc false
  def schema(resource) do
    Extension.get_opt(resource, [:clickhouse], :schema, nil, true)
  end

  @doc false
  def references(resource) do
    Extension.get_entities(resource, [:clickhouse, :references])
  end

  @doc false
  def reference(resource, relationship) do
    resource
    |> Extension.get_entities([:clickhouse, :references])
    |> Enum.find(&(&1.relationship == relationship))
  end

  @doc false
  def migration_types(resource) do
    Extension.get_opt(resource, [:clickhouse], :migration_types, [])
  end

  @doc false
  def storage_types(resource) do
    Extension.get_opt(resource, [:clickhouse], :storage_types, [])
  end

  @doc false
  def migration_defaults(resource) do
    Extension.get_opt(resource, [:clickhouse], :migration_defaults, [])
  end

  @doc false
  def migration_ignore_attributes(resource) do
    Extension.get_opt(resource, [:clickhouse], :migration_ignore_attributes, [])
  end

  @doc false
  def check_constraints(resource) do
    Extension.get_entities(resource, [:clickhouse, :check_constraints])
  end

  @doc false
  def custom_indexes(resource) do
    Extension.get_entities(resource, [:clickhouse, :custom_indexes])
  end

  @doc false
  def custom_statements(resource) do
    Extension.get_entities(resource, [:clickhouse, :custom_statements])
  end

  @doc false
  def polymorphic_on_delete(resource) do
    Extension.get_opt(resource, [:clickhouse, :references], :polymorphic_on_delete, nil, true)
  end

  @doc false
  def polymorphic_on_update(resource) do
    Extension.get_opt(resource, [:clickhouse, :references], :polymorphic_on_update, nil, true)
  end

  @doc false
  def polymorphic_name(resource) do
    Extension.get_opt(resource, [:clickhouse, :references], :polymorphic_name, nil, true)
  end

  @doc false
  def polymorphic?(resource) do
    Extension.get_opt(resource, [:clickhouse], :polymorphic?, nil, true)
  end

  @doc false
  def unique_index_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :unique_index_names, [], true)
  end

  @doc false
  def exclusion_constraint_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :exclusion_constraint_names, [], true)
  end

  @doc false
  def identity_index_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :identity_index_names, [], true)
  end

  @doc false
  def skip_identities(resource) do
    Extension.get_opt(resource, [:clickhouse], :skip_identities, [], true)
  end

  @doc false
  def foreign_key_names(resource) do
    Extension.get_opt(resource, [:clickhouse], :foreign_key_names, [], true)
  end

  @doc "Whether `mix ash.codegen` generates DDL for this resource."
  def migrate?(resource) do
    Extension.get_opt(resource, [:clickhouse], :migrate?, nil, true)
  end

  @doc false
  def global_upsert_keys(resource) do
    Extension.get_opt(resource, [:clickhouse], :global_upsert_keys, [])
  end

  @doc false
  def base_filter_sql(resource) do
    Extension.get_opt(resource, [:clickhouse], :base_filter_sql, nil)
  end

  @doc false
  def skip_unique_indexes(resource) do
    Extension.get_opt(resource, [:clickhouse], :skip_unique_indexes, [])
  end

  @doc false
  def manage_tenant_template(resource) do
    Extension.get_opt(resource, [:clickhouse, :manage_tenant], :template, nil)
  end

  @doc false
  def manage_tenant_create?(resource) do
    Extension.get_opt(resource, [:clickhouse, :manage_tenant], :create?, false)
  end

  @doc false
  def manage_tenant_update?(resource) do
    Extension.get_opt(resource, [:clickhouse, :manage_tenant], :update?, false)
  end
end
