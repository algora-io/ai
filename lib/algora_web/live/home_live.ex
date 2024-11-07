defmodule AlgoraWeb.HomeLive do
  use AlgoraWeb, :live_view

  alias Algora.Money

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       issue_url: "",
       current_issue: nil,
       similar_issues: nil,
       recommendation: nil,
       status: nil,
       error: nil,
       comments: nil
     )}
  end

  def handle_event("submit", %{"issue_url" => url}, socket) do
    send(self(), {:fetch_issue, url})

    {:noreply,
     assign(socket,
       issue_url: url,
       current_issue: nil,
       similar_issues: nil,
       recommendation: nil,
       status: "fetching_issue",
       error: nil
     )}
  end

  # Step 1: Fetch Issue
  def handle_info({:fetch_issue, url}, socket) do
    case Algora.AI.get_issue(url) do
      {:ok, issue} ->
        send(self(), {:fetch_comments, url, issue})
        {:noreply, assign(socket, current_issue: issue, status: "fetching_comments")}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "Failed to fetch issue", status: nil)}
    end
  end

  # Step 2: Fetch Comments
  def handle_info({:fetch_comments, url, issue}, socket) do
    case Algora.AI.list_comments(url) do
      {:ok, comments} ->
        send(self(), {:search_similar_issues, issue, comments})

        {:noreply,
         assign(socket,
           comments: comments,
           status: "searching_similar_issues"
         )}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "Failed to fetch comments", status: nil)}
    end
  end

  # Step 3: Search Similar Issues
  def handle_info({:search_similar_issues, issue, comments}, socket) do
    # TODO: search by title, body, and comments
    similar_issues = Algora.Workspace.search_issues(issue.title, limit: 10)
    send(self(), {:get_recommendation, issue, comments, similar_issues})

    {:noreply,
     assign(socket, similar_issues: similar_issues, status: "calculating_recommendation")}
  end

  # Step 4: Get Recommendation
  def handle_info({:get_recommendation, issue, comments, similar_issues}, socket) do
    case Algora.AI.get_bounty_recommendation(issue, comments, similar_issues) do
      {:ok, amount} ->
        {:noreply, assign(socket, recommendation: amount, status: "complete")}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "Failed to calculate recommendation", status: nil)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 font-display">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Left Column: Input and Progress -->
        <div>
          <h1 class="text-5xl font-bold">Bounty Assistant</h1>
          <p class="mt-2 text-lg text-muted-foreground">
            Get a recommended bounty for an issue on GitHub.
          </p>

          <form phx-submit="submit" class="mt-8 space-y-4 rounded-lg">
            <div class="space-y-2">
              <label class="text-base font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
                Issue URL
              </label>
              <div class="flex flex-col gap-4">
                <div class="flex-1">
                  <.input
                    type="text"
                    name="issue_url"
                    value={@issue_url}
                    placeholder="https://github.com/acme/webapp/issues/137"
                    autocomplete="off"
                    class="px-4 py-4 sm:text-xl border-muted-foreground"
                  />
                </div>
                <.button
                  type="submit"
                  size="lg"
                  disabled={@status != nil and @status != "complete"}
                  class="text-xl font-semibold py-6"
                >
                  <.icon name="tabler-sparkles" class="-ml-1 mr-2 h-8 w-8" /> Recommend bounty
                </.button>
              </div>
            </div>
          </form>

          <%= if @error do %>
            <div class="mt-4 font-medium text-destructive text-base">
              <%= @error %>
            </div>
          <% end %>

          <%= if @status do %>
            <div class="mt-4 space-y-4">
              <div class="steps space-y-2">
                <div class="flex items-center space-x-2">
                  <%= if !@current_issue do %>
                    <div class="h-4 w-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
                    <p class="text-sm text-muted-foreground">Fetching issue details...</p>
                  <% else %>
                    <.icon name="tabler-check" class="text-success h-4 w-4" />
                    <p class="text-sm text-success">Fetching issue details...</p>
                  <% end %>
                </div>

                <%= if @current_issue do %>
                  <div class="flex items-center space-x-2">
                    <%= if !@comments do %>
                      <div class="h-4 w-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
                      <p class="text-sm text-muted-foreground">Fetching comments...</p>
                    <% else %>
                      <.icon name="tabler-check" class="text-success h-4 w-4" />
                      <p class="text-sm text-success">Fetching comments...</p>
                    <% end %>
                  </div>
                <% end %>

                <%= if @comments do %>
                  <div class="flex items-center space-x-2">
                    <%= if !@similar_issues do %>
                      <div class="h-4 w-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
                      <p class="text-sm text-muted-foreground">Searching similar issues...</p>
                    <% else %>
                      <.icon name="tabler-check" class="text-success h-4 w-4" />
                      <p class="text-sm text-success">Searching similar issues...</p>
                    <% end %>
                  </div>
                <% end %>

                <%= if @similar_issues do %>
                  <div class="flex items-center space-x-2">
                    <%= if !@recommendation do %>
                      <div class="h-4 w-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
                      <p class="text-sm text-muted-foreground">Calculating recommendation...</p>
                    <% else %>
                      <.icon name="tabler-check" class="text-success h-4 w-4" />
                      <p class="text-sm text-success">Calculating recommendation...</p>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        <!-- Right Column: Only show when status exists or recommendation is ready -->
        <%= if @status || @recommendation do %>
          <div class="space-y-8">
            <div class="rounded-lg border bg-card p-6">
              <h2 class="text-lg font-semibold mb-2">Recommended Bounty</h2>
              <%= if @recommendation do %>
                <p class="text-3xl font-bold text-success">
                  <%= Money.format!(@recommendation, "USD") %>
                </p>
              <% else %>
                <p class={"text-3xl font-bold text-muted-foreground #{if @status, do: "animate-pulse"}"}>
                  $$$
                </p>
              <% end %>
            </div>

            <%= if @similar_issues do %>
              <div class="space-y-4">
                <%= if @current_issue do %>
                  <h2 class="text-lg opacity-100 truncate whitespace-nowrap">
                    <span class="font-medium text-muted-foreground">Issues similar to</span>
                    <span class="font-semibold text-foreground truncate">
                      <%= @current_issue.title %>
                    </span>
                  </h2>
                <% else %>
                  <h2 class="text-lg font-semibold opacity-0">Similar Issues</h2>
                <% end %>
                <div class="space-y-2">
                  <%= for issue <- @similar_issues do %>
                    <.link
                      href={"https://github.com/#{String.replace(issue.path, "#", "/issues/")}"}
                      target="_blank"
                      rel="noopener"
                      class="block rounded-lg border bg-card p-4 hover:bg-muted/20 transition-colors"
                    >
                      <div class="flex justify-between items-start">
                        <div class="space-y-1">
                          <p class="text-sm font-medium"><%= issue.title %></p>
                          <p class="text-xs text-muted-foreground"><%= issue.path %></p>
                        </div>
                        <span class="inline-flex items-center rounded-md bg-success/10 px-2 py-1 text-sm font-semibold text-success ring-1 ring-inset ring-success/20">
                          <%= Money.format!(issue.bounty, "USD") %>
                        </span>
                      </div>
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
