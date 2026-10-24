defmodule AshClickhouse.TestRepo.Migrations.SortReferralsByOriginType do
  use Ecto.Migration

  def up do
    execute "DROP TABLE referrals"

    execute """
    CREATE TABLE referrals (
      id UUID,
      origin JSON(type LowCardinality(String), `value.code` String, `value.url` String),
      at DateTime64(6)
    ) ENGINE = MergeTree()
        ORDER BY (origin.type, at)
    """
  end

  def down do
    execute "DROP TABLE referrals"

    execute """
    CREATE TABLE referrals (
      id UUID,
      origin JSON(`value.code` String, `value.url` String),
      at DateTime64(6)
    ) ENGINE = MergeTree()
        ORDER BY at
    """
  end
end
