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
    case fetch_issue(url) do
      {:ok, issue} ->
        case find_similar_issues(issue) do
          {:ok, top_references, similar_issues} ->
            case get_bounty_recommendation(issue, similar_issues) do
              {:ok, amount} -> {:ok, amount, top_references}
              error -> error
            end

          error ->
            error
        end

      error ->
        error
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

  def fetch_issue(url) do
    case Github.Client.get_issue_from_url(url) do
      {:ok, issue_data} -> {:ok, issue_data |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)}
      error -> error
    end
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

  def get_bounty_recommendation(issue, similar_issues) do
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
      {amount, _} -> {:ok, amount}
      _ -> {:error, :invalid_recommendation}
    end
  end

  @doc """
  Run a backtest of the bounty recommendation system on random issues.

  ## Examples:

      Algora.AI.backtest_recommendations()
      Algora.AI.backtest_recommendations(seed: 42)
  """
  def backtest_recommendations(opts \\ []) do
    Repo.transaction(fn ->
      if seed = opts[:seed] do
        :rand.seed(:exsplus, {seed, seed, seed})
        seed = :rand.uniform()
        Repo.query!("SELECT setseed($1)", [seed])
      end

      {:ok, %{rows: issues}} =
        Repo.query(
          """
          SELECT path, title, body, bounty
          FROM issues
          WHERE bounty IS NOT NULL
          ORDER BY RANDOM()
          LIMIT 2
          """,
          []
        )

      results =
        issues
        |> Enum.map(fn [path, title, body, actual_bounty] ->
          issue = %{
            path: path,
            title: title,
            body: body,
            bounty: actual_bounty
          }

          similar_issues =
            Workspace.search_issues("##{issue.title}\n\n#{issue.body}")
            |> Enum.reject(&(&1.path == issue.path))

          result =
            case get_bounty_recommendation(issue, similar_issues) do
              {:ok, recommended_bounty} ->
                %{
                  path: path,
                  actual: Decimal.new(actual_bounty),
                  recommended: recommended_bounty,
                  squared_error:
                    Decimal.mult(
                      Decimal.sub(recommended_bounty, Decimal.new(actual_bounty)),
                      Decimal.sub(recommended_bounty, Decimal.new(actual_bounty))
                    ),
                  absolute_error:
                    Decimal.abs(Decimal.sub(recommended_bounty, Decimal.new(actual_bounty)))
                }

              _ ->
                nil
            end

          # Print result immediately if valid
          if result do
            IO.puts("\n#{result.path}")
            IO.puts("  Actual: $#{result.actual}")
            IO.puts("  Recommended: $#{result.recommended}")
            IO.puts("  Absolute Error: $#{result.absolute_error}")
            IO.puts("  Squared Error: #{result.squared_error}")
          end

          result
        end)
        |> Enum.reject(&is_nil/1)

      # Calculate summary statistics
      mse =
        results
        |> Enum.map(& &1.squared_error)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        |> Decimal.div(Decimal.new(length(results)))

      rmse = Decimal.sqrt(mse)

      # Calculate median absolute error
      median_error =
        results
        |> Enum.map(& &1.absolute_error)
        |> Enum.sort_by(&Decimal.to_float/1)
        |> then(fn sorted ->
          mid = div(length(sorted), 2)

          if rem(length(sorted), 2) == 0 do
            sorted
            |> Enum.slice(mid - 1, 2)
            |> Enum.map(&Decimal.to_float/1)
            |> Enum.sum()
            |> Kernel./(2)
            |> Decimal.from_float()
          else
            Enum.at(sorted, mid)
          end
        end)

      IO.puts("\nSummary:")
      IO.puts("  Mean Squared Error: #{mse}")
      IO.puts("  Root Mean Squared Error: $#{rmse}")
      IO.puts("  Median Absolute Error: $#{median_error}")
    end)
  end
end
