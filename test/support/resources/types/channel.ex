defmodule AshClickhouse.Test.Resource.Types.Channel do
  @moduledoc """
  A union stored as its members' own maps, told apart by their `kind` tag, so
  its typed paths sit at the top of the column.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      storage: :map_with_tag,
      types: [
        email: [
          type: :map,
          tag: :kind,
          tag_value: "email",
          constraints: [
            fields: [
              kind: [type: :string, allow_nil?: false],
              address: [type: AshClickhouse.Type.ChString, allow_nil?: false]
            ]
          ]
        ],
        web: [
          type: :map,
          tag: :kind,
          tag_value: "web",
          constraints: [
            fields: [
              kind: [type: :string, allow_nil?: false],
              url: [type: AshClickhouse.Type.ChString, allow_nil?: false]
            ]
          ]
        ]
      ]
    ]

  @impl true
  def storage_type(_constraints), do: AshClickhouse.Type.ChJSON.storage_type_of(__MODULE__)
end
