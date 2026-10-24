defmodule AshClickhouse.TestRepo.Migrations.CreateContacts do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE contacts (
      id UUID,
      channel JSON(address String, url String),
      at DateTime64(6)
    ) ENGINE = MergeTree()
        ORDER BY at
    """
  end

  def down do
    execute "DROP TABLE contacts"
  end
end
