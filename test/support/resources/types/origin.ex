defmodule AshClickhouse.Test.Resource.Types.Origin do
  @moduledoc """
  A union stored as JSON in its own `{"type": ..., "value": ...}` shape, with a
  typed path into its value.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [types: [link: [type: :map, constraints: [fields: [url: [type: :string]]]]]]

  alias AshClickhouse.Type.ChJSON
  alias AshClickhouse.Type.ChString

  @impl true
  def storage_type(_constraints), do: ChJSON.storage_type(paths: %{"value.url" => ChString})
end
