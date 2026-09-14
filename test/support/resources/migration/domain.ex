defmodule AshClickhouse.Test.Migration.Domain do
  @moduledoc """
  Domain holding the resources the migration generator tests diff.

  Deliberately absent from `:ash_domains`: nothing runs DDL for these, and the
  generator tests name the domain explicitly.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshClickhouse.Test.Migration.Event)
    resource(AshClickhouse.Test.Migration.Ignored)
    resource(AshClickhouse.Test.Migration.EventsByDay)
    resource(AshClickhouse.Test.Migration.EventsByDayMv)
    resource(AshClickhouse.Test.Migration.EventCount)
    resource(AshClickhouse.Test.Migration.RawSelect)
  end
end
