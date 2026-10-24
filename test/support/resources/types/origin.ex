defmodule AshClickhouse.Test.Resource.Types.Origin do
  @moduledoc """
  A union stored as JSON in its own `{"type": ..., "value": ...}` shape, its map
  members' fields typed under `value`.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        link: [
          type: :map,
          constraints: [fields: [url: [type: AshClickhouse.Type.ChString, allow_nil?: false]]]
        ],
        campaign: [
          type: :map,
          constraints: [fields: [code: [type: AshClickhouse.Type.ChString, allow_nil?: false]]]
        ]
      ]
    ]

  @impl true
  def storage_type(_constraints), do: AshClickhouse.Type.ChJSON.storage_type_of(__MODULE__)
end
