defmodule Algora.Backtest do
  require Logger
  alias Algora.{AI, Repo, Workspace, Money}

  @doc """
  Run a backtest of the bounty recommendation system on random issues.

  ## Examples:

      Algora.Backtest.bounty_recommendations()
      Algora.Backtest.bounty_recommendations(seed: 42)
      Algora.Backtest.bounty_recommendations(limit: 10)
      Algora.Backtest.bounty_recommendations(seed: 42, limit: 5)
  """
  def bounty_recommendations(opts \\ []) do
    Repo.transaction(fn ->
      if seed = opts[:seed] do
        :rand.seed(:exsplus, {seed, seed, seed})
        seed = :rand.uniform()
        Repo.query!("SELECT setseed($1)", [seed])
      end

      limit = opts[:limit] || 2

      {:ok, %{rows: issues}} =
        Repo.query(
          """
          SELECT path, title, body, bounty
          FROM issues
          WHERE bounty IS NOT NULL
          ORDER BY RANDOM()
          LIMIT $1
          """,
          [limit]
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
            case AI.get_bounty_recommendation(issue, similar_issues) do
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
            IO.puts("  #{Money.format!(result.actual, "USD")} [actual]")
            IO.puts("  #{Money.format!(result.recommended, "USD")} [recommended]")
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
      IO.puts("  Root Mean Squared Error: #{Money.format!(rmse, "USD")}")
      IO.puts("  Median Absolute Error: #{Money.format!(median_error, "USD")}")
    end)
  end
end
