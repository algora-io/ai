defmodule Algora.Workspace.Issue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: {Nanoid, :generate, []}}
  schema "issues" do
    field :path, :string
    field :title, :string
    field :body, :string
    field :bounty, :decimal
    embeds_many :comments, Algora.Workspace.Issue.Comment

    timestamps(type: :utc_datetime)
  end

  def changeset(issue, attrs) do
    dbg(attrs)

    issue
    |> cast(attrs, [:path, :title, :body, :bounty])
    |> cast_embed(:comments, with: &comment_changeset/2)
    |> validate_required([:path, :title])
    |> unique_constraint(:path)
  end

  defp comment_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body, :actor_login, :created_at])
    |> validate_required([:body, :actor_login, :created_at])
  end
end

defmodule Algora.Workspace.Issue.Comment do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :body, :string
    field :actor_login, :string
    field :created_at, :utc_datetime
  end
end
