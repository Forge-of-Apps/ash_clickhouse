defmodule AshClickhouse.Test.Resource.Types.Visitor do
  @moduledoc "A typed struct stored as JSON, its fields of ClickHouse types as typed paths."

  use Ash.TypedStruct

  typed_struct do
    field(:user, AshClickhouse.Test.Resource.Types.Visitor.User, allow_nil?: false)
    field(:referrer, :string)
  end

  @impl true
  def storage_type(_constraints), do: AshClickhouse.Type.ChJSON.storage_type_of(__MODULE__)
end
