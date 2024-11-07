defmodule Algora.Github.Client do
  @headers [{"Accept", "application/vnd.github.v3+json"}]
  @base_url "https://api.github.com"

  def fetch(path) do
    url = "#{@base_url}/#{path}"

    request = Finch.build(:get, url, @headers)

    case Finch.request(request, Algora.Finch) do
      {:ok, response} -> Jason.decode(response.body)
      error -> error
    end
  end

  def get_issue(owner, repo, number),
    do: fetch("repos/#{owner}/#{repo}/issues/#{number}")

  def get_issue_from_url(url) do
    %{path: path} = URI.parse(url)
    [owner, repo, _, number] = String.split(path, "/", trim: true)
    get_issue(owner, repo, number)
  end

  def list_comments(owner, repo, number),
    do: fetch("repos/#{owner}/#{repo}/issues/#{number}/comments")

  def list_comments_from_url(url) do
    %{path: path} = URI.parse(url)
    [owner, repo, _, number] = String.split(path, "/", trim: true)
    list_comments(owner, repo, number)
  end
end
