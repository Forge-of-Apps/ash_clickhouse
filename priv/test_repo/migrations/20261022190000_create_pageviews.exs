defmodule AshClickhouse.TestRepo.Migrations.CreatePageviews do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE pageviews (
      id UUID,
      site String,
      visitor JSON(`user.id` String, `user.visits` UInt32),
      at DateTime64(6)
    ) ENGINE = MergeTree()
        ORDER BY (site, visitor.user.id, at)
    """
  end

  def down do
    execute "DROP TABLE pageviews"
  end
end
