defmodule Algora.Util do
  require Logger

  def with_cache(operation, items, opts) do
    cache_dir = Keyword.get(opts, :cache_dir)
    max_concurrency = Keyword.get(opts, :max_concurrency)
    batch_size = Keyword.get(opts, :batch_size)
    items_to_fetch = Enum.reject(items, &cached?(&1, cache_dir))

    if Enum.empty?(items_to_fetch) do
      {:ok, read_from_cache(items, cache_dir)}
    else
      items_to_fetch
      |> Enum.chunk_every(batch_size)
      |> Task.async_stream(operation, max_concurrency: max_concurrency, timeout: :infinity)
      |> Enum.reduce({:ok, []}, fn
        {:ok, {:ok, batch_data}}, {:ok, acc} ->
          Logger.info("Successfully processed batch with #{length(batch_data)} results")
          cache_results(batch_data, cache_dir)
          {:ok, batch_data ++ acc}

        _, error ->
          Logger.error("Batch processing failed: #{inspect(error)}")
          {:error, error}
      end)
      |> case do
        {:ok, data} -> {:ok, data ++ read_from_cache(items -- items_to_fetch, cache_dir)}
        error -> error
      end
    end
  end

  defp cached?(path, cache_dir) do
    cache_path(path, cache_dir) |> File.exists?()
  end

  defp cache_path(path, cache_dir) do
    Path.join([cache_dir, "#{path}.json"])
  end

  defp cache_results(data, cache_dir) do
    Enum.each(data, fn item = %{path: path} ->
      cache_file = cache_path(path, cache_dir)
      File.mkdir_p!(Path.dirname(cache_file))
      File.write!(cache_file, Jason.encode!(item))
    end)
  end

  defp read_from_cache(paths, cache_dir) do
    paths
    |> Enum.filter(&cached?(&1, cache_dir))
    |> Enum.map(fn path ->
      cache_path(path, cache_dir)
      |> File.read!()
      |> Jason.decode!(keys: :atoms)
    end)
  end
end
