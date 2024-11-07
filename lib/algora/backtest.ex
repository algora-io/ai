defmodule Algora.Backtest do
  require Logger
  alias Algora.{AI, Workspace, Money}

  @doc """
  Run a backtest of the bounty recommendation system on random issues.

  ## Examples:

      Algora.Backtest.bounty_recommendations()
      Algora.Backtest.bounty_recommendations(seed: 42)
      Algora.Backtest.bounty_recommendations(limit: 10)
      Algora.Backtest.bounty_recommendations(seed: 42, limit: 5)
  """
  def bounty_recommendations(_opts \\ []) do
    {:ok, issues} = Workspace.get_training_sample()

    results =
      issues
      |> Enum.map(fn issue ->
        similar_issues =
          Workspace.search_issues(
            "##{issue.title}\n\n#{issue.body}\n\nComments: #{Jason.encode!(issue.comments)}"
          )
          |> Enum.reject(&(&1.path == issue.path))

        result =
          case AI.get_bounty_recommendation(issue, issue.comments, similar_issues) do
            {:ok, recommended_bounty} ->
              %{
                path: issue.path,
                actual: Decimal.new(issue.bounty),
                recommended: recommended_bounty,
                squared_error:
                  Decimal.mult(
                    Decimal.sub(recommended_bounty, Decimal.new(issue.bounty)),
                    Decimal.sub(recommended_bounty, Decimal.new(issue.bounty))
                  ),
                absolute_error:
                  Decimal.abs(Decimal.sub(recommended_bounty, Decimal.new(issue.bounty)))
              }

            _ ->
              nil
          end

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

    # Calculate relative errors
    relative_errors =
      results
      |> Enum.map(fn result ->
        Decimal.div(
          Decimal.abs(Decimal.sub(result.recommended, result.actual)),
          result.actual
        )
        |> Decimal.mult(Decimal.new(100))
      end)

    # Calculate median relative error
    median_relative_error =
      relative_errors
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

    # Calculate average relative error
    avg_relative_error =
      relative_errors
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      |> Decimal.div(Decimal.new(length(relative_errors)))

    # Calculate average absolute error
    avg_absolute_error =
      results
      |> Enum.map(& &1.absolute_error)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      |> Decimal.div(Decimal.new(length(results)))

    # Print summary
    IO.puts("\nSummary:")
    IO.puts("  Root Mean Squared Error: #{Money.format!(Decimal.round(rmse, 0), "USD")}")
    IO.puts("  Median Absolute Error:   #{Money.format!(Decimal.round(median_error, 0), "USD")}")

    IO.puts(
      "  Average Absolute Error:  #{Money.format!(Decimal.round(avg_absolute_error, 0), "USD")}"
    )

    IO.puts("  Median Relative Error:   #{Decimal.round(median_relative_error, 0)}%")

    IO.puts("  Average Relative Error:  #{Decimal.round(avg_relative_error, 0)}%")
  end
end
