defmodule AshClickhouse.Test.Resource.Types.Visitor.User do
  @moduledoc "The user a `Visitor` nests, whose fields become typed paths under `user`."

  use Ash.TypedStruct

  typed_struct do
    field(:id, AshClickhouse.Type.ChString, allow_nil?: false)
    field(:visits, AshClickhouse.Type.ChUint32, allow_nil?: false)
    field(:plan, AshClickhouse.Type.ChString)
  end
end
