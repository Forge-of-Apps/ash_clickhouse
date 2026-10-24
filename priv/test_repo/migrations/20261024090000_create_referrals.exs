defmodule AshClickhouse.TestRepo.Migrations.CreateReferrals do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE referrals (
      id UUID,
      origin JSON(`value.code` String, `value.url` String),
      at DateTime64(6)
    ) ENGINE = MergeTree()
        ORDER BY at
    """
  end

  def down do
    execute "DROP TABLE referrals"
  end
end
