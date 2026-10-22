defmodule AshClickhouse.Test.Resource.Types.Visitor do
  @moduledoc "A JSON column with typed paths, declared once as a type of its own."

  use Ash.Type.NewType,
    subtype_of: AshClickhouse.Type.ChJSON,
    constraints: [paths: %{"user.id" => AshClickhouse.Type.ChString}]
end
