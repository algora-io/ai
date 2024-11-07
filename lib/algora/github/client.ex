defmodule Algora.Github.Client do
  @headers [{"Accept", "application/vnd.github.v3+json"}]
  @base_url "https://api.github.com"

  def fetch(path) do
    url = "#{@base_url}/#{path}"

    request = Finch.build(:get, url, @headers)

    with {:ok, response} <- request |> Finch.request(Algora.Finch),
         {:ok, data} <- Jason.decode(response.body) do
      {:ok, data}
    end
  end

  def get_issue(owner, repo, number),
    do: fetch("repos/#{owner}/#{repo}/issues/#{number}")

  def get_issue_from_url(url) do
    %{path: path} = URI.parse(url)
    [owner, repo, _, number] = String.split(path, "/", trim: true)
    get_issue(owner, repo, number)
  end
end
