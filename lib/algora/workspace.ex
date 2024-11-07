defmodule Algora.Workspace do
  import Ecto.Query
  alias Algora.Repo
  alias Algora.Workspace.Issue

  def issue_search_job_name, do: "issue_search_hf"

  def create_issue(attrs \\ %{}) do
    %Issue{}
    |> Issue.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          title: attrs.title,
          body: attrs.body,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :path
    )
  end

  def get_issue(id), do: Repo.get(Issue, id)

  def get_issue_by_path(path), do: Repo.get_by(Issue, path: path)

  def search_issues(query) do
    Repo.all(
      from(i in Issue,
        where:
          fragment(
            """
              id IN (
                SELECT i.id
                FROM vectorize.search(
                  job_name => ?,
                  query => ?,
                  return_columns => ARRAY['id'],
                  num_results => 10
                ) s
                JOIN issues i ON i.id = (s.search_results->>'id')
              )
            """,
            ^issue_search_job_name(),
            ^query
          )
      )
    )
  end
end
