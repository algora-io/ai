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
       error: nil
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
    case Algora.AI.fetch_issue(url) do
      {:ok, issue} ->
        send(self(), {:find_similar_issues, issue})
        {:noreply, assign(socket, current_issue: issue, status: "finding_similar")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Failed to fetch issue: #{reason}", status: nil)}
    end
  end

  # Step 2: Find Similar Issues
  def handle_info({:find_similar_issues, issue}, socket) do
    case Algora.AI.find_similar_issues(issue) do
      {:ok, top_references, all_similar} ->
        send(self(), {:get_recommendation, issue, all_similar})

        {:noreply,
         assign(socket, similar_issues: top_references, status: "calculating_recommendation")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Failed to find similar issues: #{reason}", status: nil)}
    end
  end

  # Step 3: Get Recommendation
  def handle_info({:get_recommendation, issue, similar_issues}, socket) do
    case Algora.AI.get_bounty_recommendation(issue, similar_issues) do
      {:ok, amount} ->
        {:noreply, assign(socket, recommendation: amount, status: "complete")}

      {:error, reason} ->
        {:noreply,
         assign(socket, error: "Failed to calculate recommendation: #{reason}", status: nil)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="py-8 px-4 sm:px-6 lg:px-8">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Left Column: Input and Progress -->
        <div>
          <h1 class="text-2xl font-display font-bold mb-4">Bounty Recommender</h1>

          <form phx-submit="submit" class="mt-4 space-y-4 rounded-lg">
            <div class="space-y-2">
              <label class="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
                Issue URL
              </label>
              <div class="flex flex-col sm:flex-row gap-2">
                <div class="flex-1">
                  <.input
                    type="text"
                    name="issue_url"
                    value={@issue_url}
                    placeholder="https://github.com/owner/repo/issues/123"
                    class="h-9"
                  />
                </div>
                <.button type="submit" disabled={@status != nil} class="w-full sm:w-auto">
                  <.icon name="tabler-search" class="-ml-1 mr-2 h-4 w-4" /> Search
                </.button>
              </div>
            </div>
          </form>

          <%= if @error do %>
            <div class="mt-4 p-4 rounded-md bg-destructive/10 text-destructive text-sm">
              <%= @error %>
            </div>
          <% end %>

          <%= if @status do %>
            <div class="mt-4 space-y-4">
              <div class="steps space-y-2">
                <div class="flex items-center space-x-2">
                  <%= if !@current_issue do %>
                    <div class="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
                    <p class="text-sm text-muted-foreground">Fetching issue details...</p>
                  <% else %>
                    <.icon name="tabler-check" class="text-success" />
                    <p class="text-sm text-success">Fetching issue details...</p>
                  <% end %>
                </div>

                <%= if @current_issue do %>
                  <div class="flex items-center space-x-2">
                    <%= if !@similar_issues do %>
                      <div class="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
                      <p class="text-sm text-muted-foreground">Finding similar issues...</p>
                    <% else %>
                      <.icon name="tabler-check" class="text-success" />
                      <p class="text-sm text-success">Finding similar issues...</p>
                    <% end %>
                  </div>
                <% end %>

                <%= if @similar_issues do %>
                  <div class="flex items-center space-x-2">
                    <%= if !@recommendation do %>
                      <div class="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
                      <p class="text-sm text-muted-foreground">Calculating recommendation...</p>
                    <% else %>
                      <.icon name="tabler-check" class="text-success" />
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
              <h2 class="text-lg font-display font-semibold mb-2">Recommended Bounty</h2>
              <%= if @recommendation do %>
                <p class="text-3xl font-display font-bold text-success">
                  <%= Money.format!(@recommendation, "USD") %>
                </p>
              <% else %>
                <p class={"text-3xl font-display font-bold text-muted-foreground #{if @status, do: "animate-pulse"}"}>
                  $$$
                </p>
              <% end %>
            </div>

            <%= if @similar_issues do %>
              <div class="space-y-4">
                <h2 class="text-lg font-display font-semibold">Similar Issues</h2>
                <div class="space-y-2 max-h-[600px] overflow-y-auto scrollbar-thin">
                  <%= for issue <- @similar_issues do %>
                    <div class="rounded-lg border bg-card p-4">
                      <div class="flex justify-between items-start">
                        <div class="space-y-1">
                          <p class="text-sm font-medium"><%= issue.title %></p>
                          <p class="text-xs text-muted-foreground"><%= issue.path %></p>
                        </div>
                        <span class="inline-flex items-center rounded-md bg-success/10 px-2 py-1 text-sm font-semibold font-display text-success ring-1 ring-inset ring-success/20">
                          <%= Money.format!(issue.bounty, "USD") %>
                        </span>
                      </div>
                    </div>
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
