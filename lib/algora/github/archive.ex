defmodule Algora.Github.Archive do
  alias Algora.Github.Archive.Client

  def list_issues(paths) do
    Client.fetch("""
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
    """)
  end
end
