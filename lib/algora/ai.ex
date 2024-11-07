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
    with {:ok, issue} <- get_issue(url),
         {:ok, top_references, similar_issues} <- find_similar_issues(issue),
         {:ok, comments} <- list_comments(url),
         {:ok, amount} <- get_bounty_recommendation(issue, comments, similar_issues) do
      {:ok, amount, top_references}
    end
  end

  @doc """
  Add training data

  ## Example:

      Algora.AI.add_training_data(["calcom/cal.com#6315", "remotion-dev/remotion#1525"])
  """
  def add_training_data(paths) do
    with {:ok, issues} <- fetch_issues(paths),
         {:ok, comments} <- fetch_comments(paths) do
      for issue <- issues do
        issue
        |> Map.put(:body, maybe_to_na(issue.body))
        |> Map.put(:comments, comments |> Enum.filter(fn c -> c.path == issue.path end))
        |> Workspace.create_issue!()
      end
    end
  end

  defp maybe_to_na(nil), do: "N/A"
  defp maybe_to_na(""), do: "N/A"
  defp maybe_to_na(value), do: value

  defp fetch_comments(paths) do
    Util.with_cache(
      &Github.Archive.list_comments/1,
      paths,
      cache_dir: ".local/comments",
      max_concurrency: @max_concurrency,
      batch_size: @batch_size
    )
  end

  defp fetch_issues(paths) do
    Util.with_cache(
      &Github.Archive.list_issues/1,
      paths,
      cache_dir: ".local/issues",
      max_concurrency: @max_concurrency,
      batch_size: @batch_size
    )
  end

  def get_issue(url) do
    case Github.Client.get_issue_from_url(url) do
      {:ok, %{"title" => title, "body" => body}} -> {:ok, %{title: title, body: body}}
      error -> error
    end
  end

  def list_comments(url) do
    try do
      {:ok, list_comments!(url)}
    rescue
      _ -> {:error, :failed_to_fetch_comments}
    end
  end

  defp list_comments!(url) do
    {:ok, comments} = Github.Client.list_comments_from_url(url)

    comments
    |> Enum.map(fn %{"body" => body, "user" => %{"login" => login}} ->
      %{body: body, user: %{login: login}}
    end)
  end

  def find_similar_issues(issue) do
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

    {:ok, top_references, similar_issues}
  end

  def get_bounty_recommendation(issue, comments, similar_issues) do
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

    prompt = """
    Based on the following issue and similar issues with their bounties, recommend an appropriate bounty amount.
    Consider the complexity implied by both the title and description, as well as patterns in existing bounties.
    Provide only a numeric response in USD (no symbols or text).

    Current Issue:
    Title: #{issue.title}
    Description: #{issue.body}
    Comments: #{Jason.encode!(comments)}

    Similar issues:
    #{issues_text}
    """

    {:ok, %{rows: [[recommendation]]}} =
      Repo.query(
        """
        SELECT vectorize.generate(
          input => $1,
          model => 'openai/gpt-4o'
        )
        """,
        [prompt]
      )

    case Decimal.parse(String.trim(recommendation)) do
      {amount, _} -> {:ok, amount}
      _ -> {:error, :invalid_recommendation}
    end
  end
end
