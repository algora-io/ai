defmodule Algora.Github.Archive.Client do
  @gh_api_url "https://gh-api.clickhouse.tech/?add_http_cors_header=1&default_format=JSONCompact&max_result_rows=1000&max_result_bytes=10000000&result_overflow_mode=break"

  @headers [{"authorization", "Basic #{System.get_env("GH_API_TOKEN")}"}]

  def fetch(query) do
    request = Finch.build(:post, @gh_api_url, @headers, query)

    with {:ok, response} <- Finch.request(request, Algora.Finch),
         {:ok, body} <- Jason.decode(response.body),
         {:ok, data} <- parse_response(body) do
      {:ok, data}
    end
  end

  defp parse_response(%{"data" => data, "meta" => meta}) do
    fields = Enum.map(meta, fn %{"name" => name} -> String.to_atom(name) end)
    {:ok, Enum.map(data, fn row -> Enum.zip(fields, row) |> Map.new() end)}
  end

  defp parse_response(_), do: {:error, :invalid_response}
end
