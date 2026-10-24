defmodule AshClickhouse.Test.Domain do
  use Ash.Domain

  resources do
    resource(AshClickhouse.Test.Resource.User)
    resource(AshClickhouse.Test.Resource.AllTypes)
    resource(AshClickhouse.Test.Resource.Organization)
    resource(AshClickhouse.Test.Resource.OrganizationUser)
    resource(AshClickhouse.Test.Resource.Pageview)
    resource(AshClickhouse.Test.Resource.Referral)
    resource(AshClickhouse.Test.Resource.Contact)
  end
end
