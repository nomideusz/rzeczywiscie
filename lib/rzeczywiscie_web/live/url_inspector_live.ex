defmodule RzeczywiscieWeb.UrlInspectorLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
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
    <.app flash={@flash} current_path={@current_path}>
    <div class="min-h-screen bg-base-200">
      <!-- Header -->
      <div class="bg-base-100 border-b-4 border-base-content">
        <div class="container mx-auto px-4 py-6">
          <.property_nav current_path={@current_path} />

          <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4 mt-4">
            <div>
              <h1 class="text-2xl md:text-3xl font-black uppercase tracking-tight">URL Inspector</h1>
              <p class="text-sm font-bold uppercase tracking-wide opacity-60">Debug URL Patterns</p>
            </div>
            <button
              phx-click="load_samples"
              disabled={@loading}
              class={"px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @loading, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}
            >
              <%= if @loading, do: "Loading...", else: "Load Sample URLs" %>
            </button>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-6">
        <%= if @loading do %>
          <div class="bg-base-100 border-2 border-base-content p-8 text-center">
            <div class="inline-block w-6 h-6 border-3 border-base-content border-t-transparent rounded-full animate-spin mb-3"></div>
            <p class="text-xs font-bold uppercase tracking-wide opacity-60">Loading sample URLs...</p>
          </div>
        <% end %>

        <%= if length(@sample_urls) > 0 do %>
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">Sample URLs (<%= length(@sample_urls) %>)</h2>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200 border-b border-base-content/30">
                  <tr>
                    <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">ID</th>
                    <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">URL</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide">Sprzedaż</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide">Wynajem</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide">Mieszkania</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/20">
                  <%= for url_info <- @sample_urls do %>
                    <tr class="hover:bg-base-200/50">
                      <td class="px-4 py-2 font-mono text-xs"><%= url_info.id %></td>
                      <td class="px-4 py-2 max-w-md">
                        <a href={url_info.url} target="_blank" rel="noopener" class="text-xs text-primary hover:underline truncate block">
                          <%= url_info.url %>
                        </a>
                      </td>
                      <td class="px-4 py-2 text-center">
                        <%= if String.contains?(url_info.url, "/sprzedaz/") do %>
                          <span class="px-2 py-0.5 text-[10px] font-bold bg-success/20 text-success">Yes</span>
                        <% else %>
                          <span class="text-xs opacity-30">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-2 text-center">
                        <%= if String.contains?(url_info.url, "/wynajem/") do %>
                          <span class="px-2 py-0.5 text-[10px] font-bold bg-warning/20 text-warning">Yes</span>
                        <% else %>
                          <span class="text-xs opacity-30">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-2 text-center">
                        <%= if String.contains?(url_info.url, "/mieszkania/") do %>
                          <span class="px-2 py-0.5 text-[10px] font-bold bg-info/20 text-info">Yes</span>
                        <% else %>
                          <span class="text-xs opacity-30">—</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% else %>
          <%= if not @loading do %>
            <div class="bg-base-100 border-2 border-base-content p-8 text-center">
              <div class="text-4xl mb-3">🔍</div>
              <h3 class="font-black uppercase tracking-wide mb-2">No URLs loaded</h3>
              <p class="text-xs opacity-60">Click "Load Sample URLs" to inspect URL patterns.</p>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    </.app>
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
