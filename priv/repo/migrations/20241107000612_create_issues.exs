defmodule Algora.Repo.Migrations.CreateIssues do
  use Ecto.Migration

  def change do
    create table(:issues, primary_key: false) do
      add :id, :string, primary_key: true
      add :path, :string, null: false
      add :title, :string, null: false
      add :bounty, :decimal
      add :body, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:issues, [:path])

    execute """
    SELECT vectorize.table(
    job_name    => '#{Algora.Workspace.issue_search_job_name()}',
    "table"     => 'issues',
    primary_key => 'id',
    columns     => ARRAY['title', 'body'],
    transformer => 'openai/text-embedding-3-small',
    schedule    => 'realtime',
    update_col  => 'updated_at'
    );
    """
  end

  def down do
    execute "DROP TABLE issues CASCADE"
  end
end
