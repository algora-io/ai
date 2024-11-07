defmodule Algora.Github.Archive do
  @moduledoc """
  Interacts with the GitHub Archive API.

  CREATE TABLE github_events
  (
      file_time DateTime,
      event_type Enum('CommitCommentEvent' = 1, 'CreateEvent' = 2, 'DeleteEvent' = 3, 'ForkEvent' = 4,
                      'GollumEvent' = 5, 'IssueCommentEvent' = 6, 'IssuesEvent' = 7, 'MemberEvent' = 8,
                      'PublicEvent' = 9, 'PullRequestEvent' = 10, 'PullRequestReviewCommentEvent' = 11,
                      'PushEvent' = 12, 'ReleaseEvent' = 13, 'SponsorshipEvent' = 14, 'WatchEvent' = 15,
                      'GistEvent' = 16, 'FollowEvent' = 17, 'DownloadEvent' = 18, 'PullRequestReviewEvent' = 19,
                      'ForkApplyEvent' = 20, 'Event' = 21, 'TeamAddEvent' = 22),
      actor_login LowCardinality(String),
      repo_name LowCardinality(String),
      created_at DateTime,
      updated_at DateTime,
      action Enum('none' = 0, 'created' = 1, 'added' = 2, 'edited' = 3, 'deleted' = 4, 'opened' = 5, 'closed' = 6, 'reopened' = 7, 'assigned' = 8, 'unassigned' = 9,
                  'labeled' = 10, 'unlabeled' = 11, 'review_requested' = 12, 'review_request_removed' = 13, 'synchronize' = 14, 'started' = 15, 'published' = 16, 'update' = 17, 'create' = 18, 'fork' = 19, 'merged' = 20),
      comment_id UInt64,
      body String,
      path String,
      position Int32,
      line Int32,
      ref LowCardinality(String),
      ref_type Enum('none' = 0, 'branch' = 1, 'tag' = 2, 'repository' = 3, 'unknown' = 4),
      creator_user_login LowCardinality(String),
      number UInt32,
      title String,
      labels Array(LowCardinality(String)),
      state Enum('none' = 0, 'open' = 1, 'closed' = 2),
      locked UInt8,
      assignee LowCardinality(String),
      assignees Array(LowCardinality(String)),
      comments UInt32,
      author_association Enum('NONE' = 0, 'CONTRIBUTOR' = 1, 'OWNER' = 2, 'COLLABORATOR' = 3, 'MEMBER' = 4, 'MANNEQUIN' = 5),
      closed_at DateTime,
      merged_at DateTime,
      merge_commit_sha String,
      requested_reviewers Array(LowCardinality(String)),
      requested_teams Array(LowCardinality(String)),
      head_ref LowCardinality(String),
      head_sha String,
      base_ref LowCardinality(String),
      base_sha String,
      merged UInt8,
      mergeable UInt8,
      rebaseable UInt8,
      mergeable_state Enum('unknown' = 0, 'dirty' = 1, 'clean' = 2, 'unstable' = 3, 'draft' = 4, 'blocked' = 5),
      merged_by LowCardinality(String),
      review_comments UInt32,
      maintainer_can_modify UInt8,
      commits UInt32,
      additions UInt32,
      deletions UInt32,
      changed_files UInt32,
      diff_hunk String,
      original_position UInt32,
      commit_id String,
      original_commit_id String,
      push_size UInt32,
      push_distinct_size UInt32,
      member_login LowCardinality(String),
      release_tag_name String,
      release_name String,
      review_state Enum('none' = 0, 'approved' = 1, 'changes_requested' = 2, 'commented' = 3, 'dismissed' = 4, 'pending' = 5)
  ) ENGINE = MergeTree ORDER BY (event_type, repo_name, created_at);
  """

  alias Algora.Github.Archive.Client

  defp path_in(paths), do: "path IN (#{paths |> Enum.map(&"'#{&1}'") |> Enum.join(",")})"

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
    AND #{path_in(paths)}
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

  def list_comments(paths) do
    query = """
    SELECT
        format('{0}\#{1}', repo_name, toString(number)) as path,
        body,
        actor_login,
        created_at
    FROM github_events
    WHERE event_type IN ('IssueCommentEvent')
    AND #{path_in(paths)}
    AND actor_login NOT LIKE '%[bot]'
    ORDER BY created_at ASC;
    """

    with {:ok, results} <- Client.fetch(query) do
      {:ok, results |> Enum.filter(fn %{body: body} -> String.split(body) |> length() >= 3 end)}
    end
  end
end
