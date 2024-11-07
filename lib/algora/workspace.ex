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

  def recommend_bounty(url) do
    %{path: path} = URI.parse(url)
    [owner, repo, _, issue_number] = String.split(path, "/", trim: true)

    api_url = "https://api.github.com/repos/#{owner}/#{repo}/issues/#{issue_number}"

    {:ok, response} =
      Finch.build(:get, api_url, [
        {"Accept", "application/vnd.github.v3+json"},
        {"User-Agent", "Algora"}
      ])
      |> Finch.request(Algora.Finch)

    issue =
      case Jason.decode!(response.body) do
        %{"title" => title, "body" => body} -> %{title: title, body: body}
      end

    similar_issues = search_issues("##{issue.title}\n\n#{issue.body}")

    top_references =
      similar_issues
      |> Enum.take(5)
      |> Enum.map(fn issue ->
        %{
          path: issue.path,
          title: issue.title,
          bounty: issue.bounty
        }
      end)

    issues_text =
      similar_issues
      |> Enum.take(100)
      |> Enum.map(fn similar_issue ->
        """
        Title: #{similar_issue.title}
        Bounty: #{similar_issue.bounty}
        """
      end)
      |> Enum.join("\n")

    {:ok, %{rows: [[recommendation]]}} =
      Repo.query(
        """
        SELECT vectorize.generate(
          input => $1,
          model => 'openai/gpt-4'
        )
        """,
        [
          """
          Based on the following issue and similar issues with their bounties, recommend an appropriate bounty amount.
          Consider the complexity implied by both the title and description, as well as patterns in existing bounties.
          Provide only a numeric response in USD (no symbols or text).

          Current Issue:
          Title: #{issue.title}
          Description: #{issue.body}

          Similar issues:
          #{issues_text}
          """
        ]
      )

    case Decimal.parse(String.trim(recommendation)) do
      {amount, _} -> {:ok, amount, top_references}
      _ -> {:error, :invalid_recommendation}
    end
  end
end
