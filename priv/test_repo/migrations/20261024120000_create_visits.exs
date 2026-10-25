defmodule AshClickhouse.TestRepo.Migrations.CreateVisits do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE visits (
      id UUID,
      page String,
      at DateTime,
      local_at DateTime('Europe/Berlin'),
      stay_days UInt16,
      on Date
    ) ENGINE = MergeTree()
        ORDER BY at
    """
  end

  def down do
    execute "DROP TABLE visits"
  end
end
