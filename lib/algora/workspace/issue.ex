defmodule Algora.Workspace.Issue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: {Nanoid, :generate, []}}
  schema "issues" do
    field :path, :string
    field :title, :string
    field :body, :string
    field :bounty, :decimal

    timestamps(type: :utc_datetime)
  end

  def changeset(issue, attrs) do
    dbg(attrs)

    issue
    |> cast(attrs, [:path, :title, :body, :bounty])
    |> validate_required([:path, :title])
    |> unique_constraint(:path)
  end
end
