defmodule AshClickhouse.Test.Domain do
  use Ash.Domain

  resources do
    resource(AshClickhouse.Test.Resource.User)
    resource(AshClickhouse.Test.Resource.AllTypes)
    resource(AshClickhouse.Test.Resource.Organization)
    resource(AshClickhouse.Test.Resource.OrganizationUser)
    resource(AshClickhouse.Test.Resource.Pageview)
  end
end
