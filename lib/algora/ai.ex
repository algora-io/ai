defmodule Algora.AI do
  require Logger
  alias Algora.{Github, Workspace, Util, Repo}

  @batch_size 20
  @max_concurrency 5

  @doc """
  Recommend a bounty for an issue

  ## Example:

      Algora.AI.recommend_bounty("https://github.com/calcom/cal.com/issues/6315")
  """
  def recommend_bounty(url) do
    issue =
      case Github.Client.get_issue_from_url(url) do
        {:ok, issue_data} -> issue_data |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      end

    similar_issues = Workspace.search_issues("##{issue.title}\n\n#{issue.body}")

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

  @doc """
  Add training data

  ## Example:

      Algora.AI.add_training_data(["calcom/cal.com#6315", "remotion-dev/remotion#1525"])
  """
  def add_training_data(paths) do
    with {:ok, issues} <- fetch_issues(paths) do
      for issue <- issues do
        Workspace.create_issue(%{issue | body: maybe_to_na(issue.body)})
      end
    end
  end

  defp maybe_to_na(nil), do: "N/A"
  defp maybe_to_na(""), do: "N/A"
  defp maybe_to_na(value), do: value

  defp fetch_issues(paths) do
    Util.with_cache(
      &Github.Archive.list_issues/1,
      paths,
      cache_dir: ".local/issues",
      max_concurrency: @max_concurrency,
      batch_size: @batch_size
    )
  end
end
