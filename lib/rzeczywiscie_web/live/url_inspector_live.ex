defmodule RzeczywiscieWeb.UrlInspectorLive do
  use RzeczywiscieWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:sample_urls, [])
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-8 max-w-4xl">
      <h1 class="text-3xl font-bold mb-6">URL Inspector</h1>

      <div class="card bg-base-200 shadow-xl mb-6">
        <div class="card-body">
          <h2 class="card-title">Sample Property URLs</h2>
          <p class="text-sm opacity-70 mb-4">
            View sample URLs from the database to understand the URL patterns.
          </p>

          <%= if @loading do %>
            <div class="alert alert-info">
              <div class="loading loading-spinner"></div>
              <span>Loading sample URLs...</span>
            </div>
          <% end %>

          <%= if length(@sample_urls) > 0 do %>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>URL</th>
                    <th>Has /sprzedaz/?</th>
                    <th>Has /wynajem/?</th>
                    <th>Has /mieszkania/?</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for url_info <- @sample_urls do %>
                    <tr>
                      <td><%= url_info.id %></td>
                      <td class="max-w-md truncate" title={url_info.url}>
                        <a href={url_info.url} target="_blank" class="link link-primary text-xs">
                          <%= url_info.url %>
                        </a>
                      </td>
                      <td>
                        <%= if String.contains?(url_info.url, "/sprzedaz/") do %>
                          <span class="badge badge-success">Yes</span>
                        <% else %>
                          <span class="badge badge-ghost">No</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if String.contains?(url_info.url, "/wynajem/") do %>
                          <span class="badge badge-success">Yes</span>
                        <% else %>
                          <span class="badge badge-ghost">No</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if String.contains?(url_info.url, "/mieszkania/") do %>
                          <span class="badge badge-success">Yes</span>
                        <% else %>
                          <span class="badge badge-ghost">No</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>

          <div class="card-actions justify-end mt-4">
            <button
              phx-click="load_samples"
              class="btn btn-primary"
              disabled={@loading}
            >
              <%= if @loading, do: "Loading...", else: "Load Sample URLs" %>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("load_samples", _params, socket) do
    Logger.info("Loading sample URLs")

    socket = assign(socket, :loading, true)

    # Run in a task
    parent = self()
    Task.start(fn ->
      samples = get_sample_urls()
      send(parent, {:samples_loaded, samples})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:samples_loaded, samples}, socket) do
    socket =
      socket
      |> assign(:loading, false)
      |> assign(:sample_urls, samples)

    {:noreply, socket}
  end

  defp get_sample_urls do
    import Ecto.Query
    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    from(p in Property,
      where: p.active == true,
      select: %{id: p.id, url: p.url},
      limit: 20
    )
    |> Repo.all()
  end
end
