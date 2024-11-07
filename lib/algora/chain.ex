defmodule Algora.Chain do
  require Logger
  alias Algora.{Github, Workspace}

  @batch_size 20
  @max_concurrency 5

  def process_body(body) do
    case body do
      "" -> "N/A"
      nil -> "N/A"
      value -> value
    end
  end

  def process_issues(paths) do
    with {:ok, issues} <- fetch_issues(paths) do
      for issue <- issues do
        Workspace.create_issue(%{issue | body: process_body(issue.body)})
      end
    end
  end

  defp fetch_issues(paths) do
    paths_to_fetch = Enum.reject(paths, &cached?/1)

    if Enum.empty?(paths_to_fetch) do
      {:ok, read_from_cache(paths)}
    else
      paths_to_fetch
      |> Enum.chunk_every(@batch_size)
      |> Task.async_stream(&Github.Archive.list_issues/1, max_concurrency: @max_concurrency)
      |> Enum.reduce({:ok, []}, fn
        {:ok, {:ok, batch_data}}, {:ok, acc} ->
          Logger.info("Successfully processed batch with #{length(batch_data)} results")
          cache_results(batch_data)
          {:ok, batch_data ++ acc}

        _, error ->
          Logger.error("Batch processing failed: #{inspect(error)}")
          {:error, error}
      end)
      |> case do
        {:ok, data} -> {:ok, data ++ read_from_cache(paths -- paths_to_fetch)}
        error -> error
      end
    end
  end

  defp cached?(path) do
    cache_path(path) |> File.exists?()
  end

  defp cache_path(path) do
    Path.join([".local", "issues", "#{path}.json"])
  end

  defp cache_results(data) do
    Enum.each(data, fn item = %{path: path} ->
      cache_file = cache_path(path)
      File.mkdir_p!(Path.dirname(cache_file))
      File.write!(cache_file, Jason.encode!(item))
    end)
  end

  defp read_from_cache(paths) do
    paths
    |> Enum.filter(&cached?/1)
    |> Enum.map(fn path ->
      cache_path(path)
      |> File.read!()
      |> Jason.decode!(keys: :atoms)
    end)
  end
end
