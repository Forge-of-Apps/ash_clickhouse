defmodule AshClickhouse.Type.Helper do
  @moduledoc false

  def find_type(graphql_types, module, short_name, default) do
    Enum.find_value(graphql_types, default, fn
      {^module, type} -> type
      {^short_name, type} -> type
      _ -> nil
    end)
  end

  defmacro graphql_type(module, short_name, default) do
    quote do
      def graphql_type(_constraints) do
        graphql_types = Application.get_env(:ash_clickhouse, :graphql_types, [])

        AshClickhouse.Type.Helper.find_type(
          graphql_types,
          unquote(module),
          unquote(short_name),
          unquote(default)
        )
      end

      def graphql_input_type(_constraints) do
        graphql_types = Application.get_env(:ash_clickhouse, :graphql_input_types, [])

        AshClickhouse.Type.Helper.find_type(
          graphql_types,
          unquote(module),
          unquote(short_name),
          unquote(default)
        )
      end
    end
  end
end
