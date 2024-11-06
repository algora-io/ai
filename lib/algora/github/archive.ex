defmodule Algora.Github.Archive do
  @gh_api_url "https://gh-api.clickhouse.tech/?add_http_cors_header=1&default_format=JSONCompact&max_result_rows=1000&max_result_bytes=10000000&result_overflow_mode=break"

  @headers [{"authorization", "Basic #{System.get_env("GH_API_TOKEN")}"}]

  def list_issues(paths) do
    body = build_query(paths)
    request = Finch.build(:post, @gh_api_url, @headers, body)

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

  defp build_query(paths) do
    """
    WITH issue_events AS (
    SELECT
        format('{0}\#{1}', repo_name, toString(number)) as path,
        title,
        body,
        action,
        created_at,
        ROW_NUMBER() OVER (PARTITION BY repo_name, number ORDER BY created_at DESC) as rn
    FROM github_events
    WHERE event_type = 'IssuesEvent'
    AND action IN ('opened', 'edited', 'closed')
    AND path IN (#{paths |> Enum.map(&"'#{&1}'") |> Enum.join(",")})
    )
    SELECT
      path,
      title,
      body
    FROM issue_events
    WHERE rn = 1
    ORDER BY created_at ASC;
    """
  end
end
