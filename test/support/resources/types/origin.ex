defmodule AshClickhouse.Test.Resource.Types.Origin do
  @moduledoc """
  A union stored as JSON in its own `{"type": ..., "value": ...}` shape: its map
  member's fields are typed under `value`, its scalar member stays dynamic.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        link: [
          type: :map,
          constraints: [fields: [url: [type: AshClickhouse.Type.ChString, allow_nil?: false]]]
        ],
        count: [type: AshClickhouse.Type.ChUint32]
      ]
    ]

  @impl true
  def storage_type(_constraints), do: AshClickhouse.Type.ChJSON.storage_type_of(__MODULE__)
end
