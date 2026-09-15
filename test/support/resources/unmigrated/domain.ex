defmodule AshClickhouse.Test.Unmigrated.Domain do
  @moduledoc """
  Domain whose every ClickHouse resource opts out of migration.

  A repo reaches the generator only through the resources that name it, so this
  is what proves a repo is still visited when none of its resources are the
  generator's to migrate — the snapshots it left behind are still its own.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshClickhouse.Test.Unmigrated.Thing)
  end
end
