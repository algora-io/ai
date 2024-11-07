defmodule Algora.Workspace do
  import Ecto.Query
  alias Algora.Repo
  alias Algora.Workspace.Issue

  def issue_search_job_name, do: "issue_search"

  def create_issue!(attrs \\ %{}) do
    {:ok, issue} = create_issue(attrs)
    issue
  end

  def create_issue(attrs \\ %{}) do
    %Issue{}
    |> Issue.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :path)
  end

  def get_issue(id), do: Repo.get(Issue, id)

  def get_issue_by_path(path), do: Repo.get_by(Issue, path: path)

  def search_issues_like(issue, opts \\ []) do
    limit = opts[:limit] || 10

    query =
      "##{issue.title}\n\n#{issue.body}\n\nComments: #{Jason.encode!(issue.comments)}"

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
                  num_results => ?
                ) s
                JOIN issues i ON i.id = (s.search_results->>'id')
              )
            """,
            ^issue_search_job_name(),
            ^query,
            ^limit
          )
      )
    )
  end

  def get_random_issues(opts \\ []) do
    limit = opts[:limit] || 2

    result =
      Repo.transaction(fn ->
        if seed = opts[:seed] do
          :rand.seed(:exsplus, {seed, seed, seed})
          seed = :rand.uniform()
          Repo.query!("SELECT setseed($1)", [seed])
        end

        Repo.all(
          from(i in Issue,
            where:
              fragment(
                """
                  id IN (
                    SELECT issues.id
                    FROM issues
                    WHERE bounty IS NOT NULL
                    ORDER BY RANDOM()
                    LIMIT ?
                  )
                """,
                ^limit
              )
          )
        )
      end)

    case result do
      {:ok, issues} -> {:ok, issues}
      {:error, reason} -> {:error, reason}
    end
  end
end
