defmodule AshClickhouse.Test.Elsewhere.Domain do
  @moduledoc """
  Domain whose views write into tables another domain owns, as a domain
  ingesting data hands it to the one keeping it.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshClickhouse.Test.Elsewhere.EventsByDayMv)
    resource(AshClickhouse.Test.Elsewhere.TableNamed)
  end
end
