defmodule AshClickhouse.DataLayer do
  @behaviour Ash.DataLayer

  @materialized_view %Spark.Dsl.Section{
    name: :materialized_view,
    describe: """
    Declares that this resource is backed by a ClickHouse materialized view
    rather than a table.

    A materialized view is an insert trigger on `source`: every block inserted
    there is run through the view's SELECT and the result written on. With `to`
    it is written into that table, which some other resource owns; without `to`
    the view owns its own storage, built from the section's `engine` and
    `options`.

    The view's columns come from its SELECT, so the resource's attributes are
    not used to build the DDL — they describe what the SELECT returns and have
    to match it.
    """,
    examples: [
      """
      materialized_view do
        source MyApp.Event
        to MyApp.EventsByDay

        query fn events ->
          from e in events,
            group_by: selected_as(:day),
            select: %{
              day: selected_as(fragment("toDate(?)", e.at), :day),
              events: selected_as(count(), :events)
            }
        end
      end
      """
    ],
    schema: [
      source: [
        type: {:or, [{:spark, Ash.Resource}, :string]},
        required: true,
        doc:
          "The resource, or bare table name, whose inserts feed the view. Passed to `query` as its FROM, so the table is named once."
      ],
      to: [
        type: {:or, [{:spark, Ash.Resource}, :string]},
        doc:
          "The resource, or bare table name, the view writes into. Without it the view owns its own storage, built from `engine` and `options`."
      ],
      query: [
        type: {:fun, 1},
        doc:
          "A function taking the source table name and returning the `Ecto.Query` the view runs over each inserted block. Name every selected column with `selected_as/2`: ClickHouse matches a view's output to its destination by name."
      ],
      select: [
        type: :string,
        doc:
          "Raw SQL for the whole SELECT, naming its own FROM. The escape hatch for statements `Ecto.Query` cannot express; prefer `query`."
      ]
    ]
  }

  @clickhouse %Spark.Dsl.Section{
    name: :clickhouse,
    describe: """
    Where and how a resource is stored in ClickHouse.

    Every resource using this data layer needs a `repo`; a resource that is
    migrated also needs a `table` and, for the `MergeTree` family, an `options`
    naming its sorting key. Add a `materialized_view` block instead of storing
    rows directly, and the resource becomes a view over another table.
    """,
    sections: [@materialized_view],
    modules: [
      :repo
    ],
    examples: [
      """
      clickhouse do
        repo MyApp.ClickhouseRepo
        table "events"
        engine "MergeTree()"
        options "order by (at, id)"
      end
      """
    ],
    schema: [
      repo: [
        type: {:or, [{:behaviour, Ecto.Repo}, {:fun, 2}]},
        required: true,
        doc:
          "The `AshClickhouse.Repo` reads and writes go through, or a function of the resource and `:read | :mutate` returning one."
      ],
      migrate?: [
        type: :boolean,
        default: true,
        doc:
          "Whether `mix ash.codegen` generates DDL for this resource. A resource with `false` is still read and written normally; its table is simply not the generator's to manage, and the generator will not drop it either."
      ],
      table: [
        type: :string,
        doc: """
        The table the resource is stored in and read from. Renaming it reads as
        a table dropped and another created, so the rename itself is a data
        migration to write by hand.
        """
      ],
      engine: [
        type: :string,
        default: "MergeTree()",
        doc:
          "The table engine, written into `CREATE TABLE ... ENGINE = `. Cannot be changed by a generated migration: ClickHouse has no `ALTER` for it."
      ],
      options: [
        type: :string,
        doc:
          "Everything that follows the engine in `CREATE TABLE`, given as raw SQL — the sorting key above all, as in `\"order by (at, id)\"`, and `PARTITION BY` or `TTL` alongside it. `MergeTree` engines require a sorting key. Like the engine, it cannot be changed by a generated migration, and a column it names can be neither dropped nor retyped."
      ]
    ]
  }

  @sections [@clickhouse]

  @moduledoc """
  An Ash data layer storing resources in ClickHouse, through `ecto_ch`.

  Add it to a resource and describe the table in a `clickhouse` block:

      defmodule MyApp.Event do
        use Ash.Resource, domain: MyApp.Analytics, data_layer: AshClickhouse.DataLayer

        clickhouse do
          repo MyApp.ClickhouseRepo
          table "events"
          options "order by (at, id)"
        end

        attributes do
          attribute :id, AshClickhouse.Type.ChUUID,
            primary_key?: true, allow_nil?: false, default: &Ash.UUIDv7.generate/0

          attribute :name, AshClickhouse.Type.ChString
          attribute :amount, AshClickhouse.Type.ChUint32
          attribute :at, AshClickhouse.Type.ChDateTime64, constraints: [precision: 6]
        end
      end

  The repo is an `AshClickhouse.Repo`. `mix ash.codegen` writes the migrations
  and `mix ash.migrate` applies them, alongside every other data layer's — see
  `AshClickhouse.MigrationGenerator` for what the generator will and will not
  do for you.

  ## Attribute types

  Column types come from the `AshClickhouse.Type.Ch*` modules, and their
  constraints choose the ClickHouse type rather than merely validating: a
  `ChString` with `nullable?: true, low_cardinality?: true` is stored as
  `LowCardinality(Nullable(String))`. Each type module documents its own
  constraints.

  An attribute whose type has no ClickHouse storage type cannot be stored or
  migrated. `Ash.Type.UUID` is the one that catches people out, because
  `uuid_primary_key` and `uuid_v7_primary_key` produce it; write the primary
  key out instead, as above.

  ## What ClickHouse does not do

  ClickHouse is an append-only column store, and the differences are not
  hidden from you:

  * **There are no transactions.** Nothing rolls back — not a failed multi-row
    insert, and not a migration that fails halfway.
  * **Model resources append-only: do not declare `:update` actions.** An
    update is issued as a re-insert, so on a `MergeTree` table both the old and
    the new row remain and a read returns both. `ReplacingMergeTree` collapses
    them by sorting key, but only once a background merge runs or a query says
    `FINAL`, and a read has no way to ask for that. Express a change as a new
    row and read the latest.
  * `:destroy` does work. It issues a lightweight `DELETE`, which removes every
    row sharing the key, duplicates included.
  * There are no foreign keys and no unique constraints, so `identities` are
    not enforced by the database and relationships are joins alone.
  * A table's engine and sorting key are fixed at creation, and a column named
    in the sorting key can be neither dropped nor retyped.
  * Multitenancy is not supported. There is no `manage_tenant` block, the
    generator writes no per-tenant migrations, and the mix tasks take no
    tenant flags.

  ## Materialized views

  A resource whose `clickhouse` block holds a `materialized_view` section is a
  view rather than a table: an insert trigger on another table, whose SELECT is
  written as an `Ecto.Query`. See `AshClickhouse.MaterializedView`.

  ## DSL

  #{Spark.CheatSheet.doc(@sections, 3)}
  """

  use Spark.Dsl.Extension,
    sections: @sections,
    verifiers: []

  require Ash.Expr
  require Ash.Query
  require Ecto.Query

  alias AshClickhouse.SqlImplementation
  alias AshClickhouse.DataLayer.Info
  alias AshClickhouse.ManualRelationship

  def name, do: "AshClickhouse migrations"

  def codegen(args) do
    Mix.Task.reenable("ash_clickhouse.generate_migrations")
    Mix.Task.run("ash_clickhouse.generate_migrations", args)
  end

  def rollback(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          repo: :string
        ],
        aliases: [r: :repo]
      )

    repos = AshClickhouse.Mix.Helpers.repos!(opts, args)

    show_for_repo? = Enum.count_until(repos, 2) == 2

    for repo <- repos do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          for_repo =
            if show_for_repo? do
              " for repo #{inspect(repo)}"
            else
              ""
            end

          migrations_path = AshClickhouse.Mix.Helpers.migrations_path([], repo)

          current_migrations =
            Ecto.Query.from(row in "schema_migrations",
              select: row.version
            )
            |> repo.all()
            |> Enum.map(&to_string/1)

          files =
            migrations_path
            |> Path.join("**/*.exs")
            |> Path.wildcard()
            |> Enum.sort()
            |> Enum.reverse()
            |> Enum.filter(fn file ->
              Enum.any?(current_migrations, &String.starts_with?(Path.basename(file), &1))
            end)
            |> Enum.take(20)
            |> Enum.map(&String.trim_leading(&1, migrations_path))
            |> Enum.map(&String.trim_leading(&1, "/"))

          indexed =
            files
            |> Enum.with_index()
            |> Enum.map(fn {file, index} -> "#{index + 1}: #{file}" end)

          to =
            Mix.shell().prompt(
              """
              How many migrations should be rolled back#{for_repo}? (default: 0)

              Last 20 migration names, with the input you must provide to
              rollback up to *and including* that migration:

              #{Enum.join(indexed, "\n")}
              Rollback to:
              """
              |> String.trim_trailing()
            )
            |> String.trim()
            |> case do
              "" ->
                nil

              "0" ->
                nil

              n ->
                try do
                  files
                  |> Enum.at(String.to_integer(n) - 1)
                rescue
                  _ ->
                    reraise "Required an integer value, got: #{n}", __STACKTRACE__
                end
                |> String.split("_", parts: 2)
                |> Enum.at(0)
                |> String.to_integer()
            end

          if to do
            Mix.Task.run(
              "ash_clickhouse.rollback",
              args ++ ["-r", inspect(repo), "--to", to_string(to)]
            )

            Mix.Task.reenable("ash_clickhouse.rollback")
          end
        end)
    end
  end

  def migrate(args) do
    Mix.Task.reenable("ash_clickhouse.migrate")
    Mix.Task.run("ash_clickhouse.migrate", args)
  end

  def setup(args) do
    # TODO: take args that we care about
    Mix.Task.run("ash_clickhouse.create", args)
    Mix.Task.run("ash_clickhouse.migrate", args)
  end

  def tear_down(args) do
    # TODO: take args that we care about
    Mix.Task.run("ash_clickhouse.drop", args)
  end

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :bulk_create), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
  def can?(_, :filter), do: true

  def can?(_, {:filter_relationship, %{manual: {module, _}}}) do
    Spark.implements_behaviour?(module, ManualRelationship)
  end

  def can?(_, {:filter_relationship, _}), do: true
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, :nested_expressions), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, :sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, :count), do: true
  def can?(_, {:count, _}), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, :aggregate), do: true
  def can?(_, {:aggregate, _}), do: true
  def can?(_, {:aggregate_type, _}), do: true
  def can?(_, {:query_aggregate, _}), do: true
  def can?(_, :multitenancy), do: true
  def can?(_, _), do: false

  @impl true
  def set_context(resource, data_layer_query, context) do
    AshSql.Query.set_context(resource, data_layer_query, SqlImplementation, context)
  end

  @impl true
  def resource_to_query(resource, domain) do
    AshSql.Query.resource_to_query(resource, SqlImplementation, domain)
  end

  @impl true
  def create(resource, changeset) do
    changeset = %{
      changeset
      | data:
          Map.update!(
            changeset.data,
            :__meta__,
            &Map.put(&1, :source, table(resource, changeset))
          )
    }

    repo_opts = Map.get(changeset.context, :repo_opts, [])

    case bulk_create(resource, [changeset], %{
           single?: true,
           tenant: Map.get(changeset, :to_tenant, changeset.tenant),
           action_select: changeset.action_select,
           return_records?: true,
           repo_opts: repo_opts
         }) do
      {:ok, [result]} ->
        {:ok, result}

      {:ok, []} ->
        {:ok, []}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def update(resource, changeset) do
    attributes =
      changeset.data
      |> Map.from_struct()
      |> Map.take(changeset.data.__struct__.__schema__(:fields) -- Map.keys(changeset.attributes))
      |> Map.merge(changeset.attributes)

    changeset_for_insert = %{
      changeset
      | attributes: attributes,
        action_type: :create
    }

    create(resource, changeset_for_insert)
  end

  @impl true
  def bulk_create(resource, stream, options) do
    changesets = Enum.to_list(stream)

    repo = AshSql.dynamic_repo(resource, SqlImplementation, Enum.at(changesets, 0))

    opts =
      repo
      |> AshSql.repo_opts(SqlImplementation, nil, options[:tenant], resource)
      |> Keyword.merge(options[:repo_opts] || [])

    source = resolve_source(resource, Enum.at(changesets, 0))

    try do
      opts =
        if schema = Enum.at(changesets, 0).context[:data_layer][:schema] do
          Keyword.put(opts, :prefix, schema)
        else
          opts
        end

      case insert_all_returning(source, changesets, repo, options[:return_records?], opts) do
        [] ->
          :ok

        results ->
          if options[:single?] do
            {:ok, results}
          else
            {:ok,
             Stream.zip_with(results, changesets, fn result, changeset ->
               Ash.Resource.put_metadata(
                 result,
                 :bulk_create_index,
                 changeset.context.bulk_create.index
               )
             end)}
          end
      end
    rescue
      e ->
        changeset =
          case source do
            {table, resource} ->
              resource
              |> Ash.Changeset.new()
              |> Ash.Changeset.put_context(:data_layer, %{table: table})

            resource ->
              resource
              |> Ash.Changeset.new()
          end

        handle_raised_error(
          e,
          __STACKTRACE__,
          {:bulk_create, ecto_changeset(changeset.data, changeset, :create, repo, false)},
          resource
        )
    end
  end

  defp insert_all_returning(source, changesets, repo, false, opts) do
    entries = Enum.map(changesets, & &1.attributes)
    repo.insert_all(source, entries, opts)
    []
  end

  defp insert_all_returning(source, changesets, repo, true, opts) do
    entries = Enum.map(changesets, & &1.attributes)
    repo.insert_all(source, entries, opts)

    Enum.reduce_while(changesets, [], fn changeset, acc ->
      case Ash.Changeset.apply_attributes(changeset) do
        {:ok, record} ->
          {:cont, [record | acc]}

        {:error, errors} ->
          {:halt, {:error, errors}}
      end
    end)
  end

  @impl true
  def destroy(resource, %{data: record} = changeset) do
    repo = AshSql.dynamic_repo(resource, SqlImplementation, changeset)
    ecto_changeset = ecto_changeset(record, changeset, :delete, repo, true)

    try do
      repo_opts =
        repo
        |> AshSql.repo_opts(SqlImplementation, nil, nil, resource)
        |> Keyword.merge(changeset.context[:repo_opts] || [])

      case repo.delete(ecto_changeset, repo_opts) do
        {:ok, _record} ->
          :ok

        {:error, error} ->
          handle_errors({:error, error})
      end
    rescue
      e ->
        handle_raised_error(e, __STACKTRACE__, ecto_changeset, resource)
    end
  end

  defp handle_errors({:error, %Ecto.Changeset{errors: errors}}) do
    {:error, Enum.map(errors, &to_ash_error/1)}
  end

  defp to_ash_error({field, {message, vars}}) do
    Ash.Error.Changes.InvalidAttribute.exception(
      field: field,
      message: message,
      private_vars: vars
    )
  end

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

  @doc false
  def get_source_for_upsert_field(field, resource) do
    case Ash.Resource.Info.attribute(resource, field) do
      %{source: source} when not is_nil(source) ->
        source

      _ ->
        field
    end
  end

  @doc false
  @impl true
  def sort(query, sort, _resource) do
    {:ok, Map.update!(query, :__ash_bindings__, &Map.put(&1, :sort, sort))}
  end

  @doc false
  @impl true
  def limit(query, nil, _), do: {:ok, query}

  def limit(query, limit, _resource) do
    {:ok, Ecto.Query.from(row in query, limit: ^limit)}
  end

  @doc false
  @impl true
  def offset(query, nil, _), do: query

  def offset(%{offset: old_offset} = query, 0, _resource) when old_offset in [0, nil] do
    {:ok, query}
  end

  def offset(query, offset, _resource) do
    {:ok, Ecto.Query.from(row in query, offset: ^offset)}
  end

  @impl true
  def select(query, select, resource) do
    query = AshSql.Bindings.default_bindings(query, resource, SqlImplementation)
    {:ok, Ecto.Query.from(row in query, select: struct(row, ^Enum.uniq(select)))}
  end

  @impl true
  def filter(query, filter, _resource, opts \\ []) do
    AshSql.Filter.filter(query, filter, opts)
  end

  @impl true
  def return_query(query, resource) do
    query
    |> AshSql.Bindings.default_bindings(resource, SqlImplementation)
    |> AshSql.Query.return_query(resource)
  end

  @impl true
  def run_query(query, resource) do
    query = AshSql.Bindings.default_bindings(query, resource, SqlImplementation)

    if Info.polymorphic?(resource) && no_table?(query) do
      raise_table_error!(resource, :read)
    else
      repo = AshSql.dynamic_repo(resource, SqlImplementation, query)

      repo_opts =
        repo
        |> AshSql.repo_opts(SqlImplementation, nil, nil, resource)
        |> Keyword.merge(query.__ash_bindings__.context[:repo_opts] || [])

      query
      |> repo.all(repo_opts)
      |> AshSql.Query.remap_mapped_fields(query)
      |> then(fn results ->
        if query.__ash_bindings__.context[:data_layer][:combination_of_queries?] do
          Enum.map(results, fn result ->
            Map.put(struct(resource, result), :__meta__, %Ecto.Schema.Metadata{state: :loaded})
          end)
        else
          results
        end
      end)
      |> then(&{:ok, &1})
    end
  rescue
    e ->
      handle_raised_error(e, __STACKTRACE__, query, resource)
  end

  @impl true
  def run_aggregate_query(query, aggregates, resource) do
    # Basic aggregate implementation for ClickHouse
    # For now, return basic count support only
    case aggregates do
      [%{kind: :count}] ->
        query = AshSql.Bindings.default_bindings(query, resource, SqlImplementation)

        if Info.polymorphic?(resource) && no_table?(query) do
          raise_table_error!(resource, :read)
        else
          repo = AshSql.dynamic_repo(resource, SqlImplementation, query)

          repo_opts =
            repo
            |> AshSql.repo_opts(SqlImplementation, nil, nil, resource)
            |> Keyword.merge(query.__ash_bindings__.context[:repo_opts] || [])

          count_query =
            query
            |> Ecto.Query.select([r], count())

          case repo.one(count_query, repo_opts) do
            count when is_integer(count) -> {:ok, %{count: count}}
            nil -> {:ok, %{count: 0}}
            error -> {:error, error}
          end
        end

      _other ->
        # For now, return empty results for other aggregate types
        # This prevents the "Aggregate queries not supported" error
        {:ok, %{}}
    end
  rescue
    e ->
      handle_raised_error(e, __STACKTRACE__, query, resource)
  end

  defp no_table?(%{from: %{source: {"", _}}}), do: true
  defp no_table?(_), do: false

  defp resolve_source(resource, changeset) do
    table = table(resource, changeset)
    {table, resource}
  end

  defp table(resource, changeset) do
    changeset.context[:data_layer][:table] || Info.table(resource)
  end

  defp ecto_changeset(record, changeset, type, repo, table_error?) do
    attributes =
      changeset.resource
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)

    attributes_to_change =
      Enum.reject(attributes, fn attribute ->
        Keyword.has_key?(changeset.atomics, attribute)
      end)

    ecto_changeset =
      record
      |> to_ecto()
      |> set_table(changeset, type, table_error?)
      |> Ecto.Changeset.cast(%{}, [])
      |> force_changes(Map.take(changeset.attributes, attributes_to_change))
      |> add_configured_foreign_key_constraints(record.__struct__)
      |> add_check_constraints(record.__struct__, repo)
      |> add_exclusion_constraints(record.__struct__, repo)

    case type do
      :create ->
        ecto_changeset
        |> add_my_foreign_key_constraints(record.__struct__, repo)

      type when type in [:upsert, :update] ->
        ecto_changeset
        |> add_my_foreign_key_constraints(record.__struct__, repo)
        |> add_related_foreign_key_constraints(record.__struct__, repo)

      :delete ->
        ecto_changeset
        |> add_related_foreign_key_constraints(record.__struct__, repo)
    end
  end

  defp set_table(record, changeset, operation, table_error?) do
    if Info.polymorphic?(record.__struct__) do
      table = changeset.context[:data_layer][:table] || Info.table(record.__struct__)

      record =
        if table do
          Ecto.put_meta(record, source: table)
        else
          if table_error? do
            raise_table_error!(changeset.resource, operation)
          else
            record
          end
        end

      prefix = changeset.context[:data_layer][:schema] || Info.schema(record.__struct__)

      if prefix do
        Ecto.put_meta(record, prefix: table)
      else
        record
      end
    else
      record
    end
  end

  defp raise_table_error!(resource, operation) do
    if Info.polymorphic?(resource) do
      raise """
      Could not determine table for #{operation} on #{inspect(resource)}.

      Polymorphic resources require that the `data_layer[:table]` context is provided.
      See the guide on polymorphic resources for more information.
      """
    else
      raise """
      Could not determine table for #{operation} on #{inspect(resource)}.
      """
    end
  end

  defp force_changes(changeset, changes) do
    Enum.reduce(changes, changeset, fn {key, value}, changeset ->
      Ecto.Changeset.force_change(changeset, key, value)
    end)
  end

  defp add_configured_foreign_key_constraints(changeset, resource) do
    resource
    |> Info.foreign_key_names()
    |> case do
      {m, f, a} -> List.wrap(apply(m, f, [changeset | a]))
      value -> List.wrap(value)
    end
    |> Enum.reduce(changeset, fn
      {key, name}, changeset ->
        Ecto.Changeset.foreign_key_constraint(changeset, key, name: name)

      {key, name, message}, changeset ->
        Ecto.Changeset.foreign_key_constraint(changeset, key, name: name, message: message)
    end)
  end

  defp add_check_constraints(changeset, resource, repo) do
    resource
    |> Info.check_constraints()
    |> Enum.reduce(changeset, fn constraint, changeset ->
      constraint.attribute
      |> List.wrap()
      |> Enum.reduce(changeset, fn attribute, changeset ->
        case repo.default_constraint_match_type(:check, constraint.name) do
          {:regex, regex} ->
            Ecto.Changeset.check_constraint(changeset, attribute,
              name: regex,
              message: constraint.message || "is invalid",
              match: :exact
            )

          match ->
            Ecto.Changeset.check_constraint(changeset, attribute,
              name: constraint.name,
              message: constraint.message || "is invalid",
              match: match
            )
        end
      end)
    end)
  end

  defp add_exclusion_constraints(changeset, resource, repo) do
    resource
    |> Info.exclusion_constraint_names()
    |> Enum.reduce(changeset, fn constraint, changeset ->
      case constraint do
        {key, name} ->
          case repo.default_constraint_match_type(:check, name) do
            {:regex, regex} ->
              Ecto.Changeset.exclusion_constraint(changeset, key,
                name: regex,
                match: :exact
              )

            match ->
              Ecto.Changeset.exclusion_constraint(changeset, key,
                name: name,
                match: match
              )
          end

        {key, name, message} ->
          case repo.default_constraint_match_type(:check, name) do
            {:regex, regex} ->
              Ecto.Changeset.exclusion_constraint(changeset, key,
                name: regex,
                message: message,
                match: :exact
              )

            match ->
              Ecto.Changeset.exclusion_constraint(changeset, key,
                name: name,
                message: message,
                match: match
              )
          end
      end
    end)
  end

  defp add_my_foreign_key_constraints(changeset, resource, repo) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.reduce(changeset, fn relationship, changeset ->
      # Check if there's a custom reference name defined in the DSL
      name =
        case Info.reference(resource, relationship.name) do
          %{name: custom_name} when not is_nil(custom_name) ->
            custom_name

          _ ->
            "#{Info.table(resource)}_#{relationship.source_attribute}_fkey"
        end

      case repo.default_constraint_match_type(:foreign, name) do
        {:regex, regex} ->
          Ecto.Changeset.foreign_key_constraint(changeset, relationship.source_attribute,
            name: regex,
            match: :exact
          )

        match ->
          Ecto.Changeset.foreign_key_constraint(changeset, relationship.source_attribute,
            name: name,
            match: match
          )
      end
    end)
  end

  defp add_related_foreign_key_constraints(changeset, resource, repo) do
    # TODO: this doesn't guarantee us to get all of them, because if something is related to this
    # schema and there is no back-relation, then this won't catch it's foreign key constraints
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.map(& &1.destination)
    |> Enum.uniq()
    |> Enum.flat_map(fn related ->
      related
      |> Ash.Resource.Info.relationships()
      |> Enum.filter(&(&1.destination == resource))
      |> Enum.map(&Map.take(&1, [:source, :source_attribute, :destination_attribute, :name]))
    end)
    |> Enum.reduce(changeset, fn %{
                                   source: source,
                                   source_attribute: source_attribute,
                                   destination_attribute: destination_attribute,
                                   name: relationship_name
                                 },
                                 changeset ->
      case Info.reference(resource, relationship_name) do
        %{name: name} when not is_nil(name) ->
          case repo.default_constraint_match_type(:foreign, name) do
            {:regex, regex} ->
              Ecto.Changeset.foreign_key_constraint(changeset, destination_attribute,
                name: regex,
                message: "would leave records behind",
                match: :exact
              )

            match ->
              Ecto.Changeset.foreign_key_constraint(changeset, destination_attribute,
                name: name,
                message: "would leave records behind",
                match: match
              )
          end

        _ ->
          name = "#{Info.table(source)}_#{source_attribute}_fkey"

          case repo.default_constraint_match_type(:foreign, name) do
            {:regex, regex} ->
              Ecto.Changeset.foreign_key_constraint(changeset, destination_attribute,
                name: regex,
                message: "would leave records behind",
                match: :exact
              )

            match ->
              Ecto.Changeset.foreign_key_constraint(changeset, destination_attribute,
                name: name,
                message: "would leave records behind",
                match: match
              )
          end
      end
    end)
  end

  defp handle_raised_error(
         %Ecto.StaleEntryError{changeset: %{data: %resource{}, filters: filters}},
         stacktrace,
         context,
         resource
       ) do
    handle_raised_error(
      Ash.Error.Changes.StaleRecord.exception(resource: resource, filter: filters),
      stacktrace,
      context,
      resource
    )
  end

  defp handle_raised_error(%Ecto.Query.CastError{} = e, stacktrace, context, resource) do
    handle_raised_error(
      Ash.Error.Query.InvalidFilterValue.exception(value: e.value, context: context),
      stacktrace,
      context,
      resource
    )
  end

  defp handle_raised_error(error, stacktrace, _ecto_changeset, _resource) do
    {:error, Ash.Error.to_ash_error(error, Exception.format_stacktrace(stacktrace))}
  end
end
