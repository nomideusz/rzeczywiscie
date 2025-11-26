defmodule RzeczywiscieWeb.LifeRebootLive do
  use RzeczywiscieWeb, :live_view
  alias Rzeczywiscie.LifeReboot

  # Reminder schedule (hours in local time, roughly)
  # These will trigger if you haven't taken meds yet
  @meds_reminder_hours [10, 14, 18, 21]
  @social_reminder_days 3  # Remind after 3 days of no interaction

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      LifeReboot.subscribe()
      LifeReboot.ensure_medication_settings()
      schedule_reminders()
    end

    socket =
      socket
      |> assign(:dismissed_reminders, MapSet.new())
      |> load_dashboard_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-neutral-50">
      <!-- Minimal Header -->
      <header class="border-b border-neutral-200 bg-white">
        <div class="max-w-2xl mx-auto px-4 py-4 flex justify-between items-center">
          <div>
            <h1 class="text-lg font-semibold text-neutral-900">Life</h1>
            <p class="text-xs text-neutral-500"><%= Calendar.strftime(Date.utc_today(), "%A, %B %d") %></p>
          </div>
          <%= if @data.checkin_streak > 0 do %>
            <div class="text-right">
              <div class="text-2xl font-bold text-neutral-900"><%= @data.checkin_streak %></div>
              <div class="text-xs text-neutral-500">day streak</div>
            </div>
          <% end %>
        </div>
      </header>

      <!-- Reminder Banners -->
      <%= if assigns[:show_meds_reminder] do %>
        <div class="bg-amber-50 border-b border-amber-200">
          <div class="max-w-2xl mx-auto px-4 py-3 flex justify-between items-center">
            <div class="flex items-center gap-3">
              <span class="text-amber-600">●</span>
              <span class="text-sm text-amber-900"><%= @reminder_message %></span>
            </div>
            <div class="flex gap-2">
              <button class="text-xs font-medium text-amber-700 hover:text-amber-900 px-2 py-1" phx-click="dismiss_meds_reminder">
                Dismiss
              </button>
              <button class="text-xs font-medium bg-amber-600 text-white px-3 py-1 rounded hover:bg-amber-700" phx-click="log_meds">
                Log now
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%= if assigns[:show_social_reminder] do %>
        <div class="bg-blue-50 border-b border-blue-200">
          <div class="max-w-2xl mx-auto px-4 py-3 flex justify-between items-center">
            <div class="flex items-center gap-3">
              <span class="text-blue-600">●</span>
              <span class="text-sm text-blue-900"><%= @social_reminder_message %></span>
            </div>
            <div class="flex gap-2">
              <button class="text-xs font-medium text-blue-700 hover:text-blue-900 px-2 py-1" phx-click="dismiss_social_reminder">
                Dismiss
              </button>
              <button class="text-xs font-medium bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700" phx-click="log_social">
                Log chat
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <main class="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <!-- Status Cards - These ARE the actions -->
        <% meds = @data.medication_status %>

        <!-- Meds Card -->
        <button class={"w-full text-left p-4 rounded-lg border transition-all " <> cond do
          meds.over_limit -> "bg-red-50 border-red-200"
          meds.at_limit -> "bg-neutral-900 text-white border-neutral-900"
          meds.pills_taken_today > 0 -> "bg-green-50 border-green-200"
          true -> "bg-white border-neutral-200 hover:border-neutral-300"
        end} phx-click="log_meds">
          <div class="flex justify-between items-start">
            <div>
              <div class={"text-xs font-medium uppercase tracking-wide " <> if(meds.at_limit, do: "text-neutral-400", else: "text-neutral-500")}>Medication</div>
              <div class={"text-2xl font-bold " <> if(meds.at_limit, do: "text-white", else: "text-neutral-900")}>
                <%= meds.pills_taken_today %> / <%= meds.pills_max_allowed %>
              </div>
              <%= case meds.taper_status do %>
                <% {:tapering, days} -> %>
                  <div class={"text-xs mt-1 " <> if(meds.at_limit, do: "text-neutral-400", else: "text-neutral-500")}>
                    <%= days %> days until limit drops to <%= meds.pills_prescribed %>
                  </div>
                <% _ -> %>
              <% end %>
            </div>
            <div class={"text-xs font-medium " <> if(meds.at_limit, do: "text-neutral-400", else: "text-neutral-500")}>
              <%= if meds.pills_remaining > 0, do: "#{meds.pills_remaining} remaining", else: "limit reached" %>
            </div>
          </div>
        </button>

        <!-- Social Card -->
        <% days = @data.days_since_any_interaction %>
        <button class={"w-full text-left p-4 rounded-lg border transition-all " <> cond do
          days == nil -> "bg-white border-neutral-200 hover:border-neutral-300"
          days >= 7 -> "bg-amber-50 border-amber-200"
          days == 0 -> "bg-green-50 border-green-200"
          true -> "bg-white border-neutral-200 hover:border-neutral-300"
        end} phx-click="log_social">
          <div class="flex justify-between items-start">
            <div>
              <div class="text-xs font-medium uppercase tracking-wide text-neutral-500">Social</div>
              <div class="text-2xl font-bold text-neutral-900">
                <%= cond do %>
                  <% days == nil -> %>—
                  <% days == 0 -> %>Today
                  <% true -> %><%= days %>d ago
                <% end %>
              </div>
              <%= cond do %>
                <% days == nil -> %>
                  <div class="text-xs mt-1 text-neutral-500">Log your first conversation</div>
                <% days >= 5 -> %>
                  <div class="text-xs mt-1 text-neutral-500">Time for a real conversation?</div>
                <% true -> %>
              <% end %>
            </div>
            <div class="text-xs font-medium text-neutral-500">
              <%= if days == nil, do: "tap to log", else: "last interaction" %>
            </div>
          </div>
        </button>

        <!-- Mood Card -->
        <button class="w-full text-left p-4 rounded-lg border bg-white border-neutral-200 hover:border-neutral-300 transition-all"
                phx-click="log_mood">
          <div class="flex justify-between items-start">
            <div>
              <div class="text-xs font-medium uppercase tracking-wide text-neutral-500">Mood</div>
              <div class="text-2xl font-bold text-neutral-900">
                <%= if @data.mood_trends.average_mood, do: "#{@data.mood_trends.average_mood}/5", else: "—" %>
              </div>
              <%= if @data.mood_trends.average_job_dread do %>
                <div class="text-xs mt-1 text-neutral-500">Job dread: <%= @data.mood_trends.average_job_dread %>/10</div>
              <% end %>
            </div>
            <div class="text-xs font-medium text-neutral-500">7-day avg</div>
          </div>
        </button>

        <!-- Debt Card -->
        <%= if length(@data.debts) > 0 or @data.debt_stats.total_owed != Decimal.new(0) do %>
          <button class="w-full text-left p-4 rounded-lg border bg-white border-neutral-200 hover:border-neutral-300 transition-all"
                  phx-click="show_debt_section">
            <div class="flex justify-between items-start">
              <div>
                <div class="text-xs font-medium uppercase tracking-wide text-neutral-500">Debt Progress</div>
                <div class="text-2xl font-bold text-neutral-900"><%= Float.round(@data.debt_stats.progress_percent, 1) %>%</div>
              </div>
              <div class="text-right">
                <div class="text-xs font-medium text-neutral-500"><%= format_currency(@data.debt_stats.total_paid) %> paid</div>
                <div class="text-xs text-neutral-400"><%= format_currency(@data.debt_stats.total_owed) %> remaining</div>
              </div>
            </div>
            <!-- Progress bar -->
            <div class="mt-3 h-2 bg-neutral-100 rounded-full overflow-hidden">
              <div class="h-full bg-neutral-900 rounded-full transition-all" style={"width: #{@data.debt_stats.progress_percent}%"}></div>
            </div>
          </button>
        <% end %>

        <!-- Daily Check-in -->
        <div class="mt-8 pt-6 border-t border-neutral-200">
          <%= if @data.today_checkin && @data.today_checkin.completed_at do %>
            <div class="p-4 rounded-lg bg-green-50 border border-green-200">
              <div class="flex justify-between items-start">
                <div>
                  <div class="text-sm font-medium text-green-900">Check-in complete</div>
                  <%= if @data.today_checkin.small_win do %>
                    <div class="text-xs text-green-700 mt-1">Win: <%= @data.today_checkin.small_win %></div>
                  <% end %>
                </div>
                <button class="text-xs font-medium text-green-700 hover:text-green-900" phx-click="start_checkin">
                  Edit
                </button>
              </div>
            </div>
          <% else %>
            <button class="w-full p-4 rounded-lg bg-neutral-900 text-white font-medium hover:bg-neutral-800 transition-colors"
                    phx-click="start_checkin">
              Daily Check-in →
            </button>
          <% end %>
        </div>

        <!-- Encouragement -->
        <div class="text-center py-4 text-sm text-neutral-400">
          <%= encouragement_message(@data) %>
        </div>

        <!-- Weekly History Toggle -->
        <div class="mt-4 pt-4 border-t border-neutral-200">
          <button class="w-full text-center text-sm text-neutral-500 hover:text-neutral-700 py-2"
                  phx-click="toggle_history">
            <%= if @show_history do %>
              Hide week ↑
            <% else %>
              Show week ↓
            <% end %>
          </button>

          <%= if @show_history do %>
            <div class="mt-4 p-4 bg-white rounded-lg border border-neutral-200">
              <div class="text-xs font-medium uppercase tracking-wide text-neutral-500 mb-4">Last 7 days</div>

              <!-- Day headers -->
              <div class="grid grid-cols-7 gap-1 mb-2">
                <%= for day <- @weekly_history do %>
                  <div class={"text-center text-xs font-medium " <> if(day.is_today, do: "text-neutral-900", else: "text-neutral-400")}>
                    <%= day.day_name %>
                  </div>
                <% end %>
              </div>

              <!-- Meds row -->
              <div class="grid grid-cols-7 gap-1 mb-1">
                <%= for day <- @weekly_history do %>
                  <div class={"h-8 rounded flex items-center justify-center text-xs font-medium " <> cond do
                    day.meds == 0 -> "bg-neutral-100 text-neutral-400"
                    day.meds <= 2 -> "bg-green-100 text-green-700"
                    day.meds == 3 -> "bg-amber-100 text-amber-700"
                    true -> "bg-red-100 text-red-700"
                  end}>
                    <%= if day.meds > 0, do: day.meds, else: "—" %>
                  </div>
                <% end %>
              </div>
              <div class="text-xs text-neutral-400 mb-3">Pills</div>

              <!-- Social row -->
              <div class="grid grid-cols-7 gap-1 mb-1">
                <%= for day <- @weekly_history do %>
                  <div class={"h-8 rounded flex items-center justify-center text-xs " <> if(day.social, do: "bg-green-100 text-green-700", else: "bg-neutral-100 text-neutral-400")}>
                    <%= if day.social, do: "✓", else: "—" %>
                  </div>
                <% end %>
              </div>
              <div class="text-xs text-neutral-400 mb-3">Social</div>

              <!-- Mood row -->
              <div class="grid grid-cols-7 gap-1 mb-1">
                <%= for day <- @weekly_history do %>
                  <div class={"h-8 rounded flex items-center justify-center text-xs font-medium " <> cond do
                    day.mood == nil -> "bg-neutral-100 text-neutral-400"
                    day.mood >= 4 -> "bg-green-100 text-green-700"
                    day.mood >= 3 -> "bg-blue-100 text-blue-700"
                    day.mood >= 2 -> "bg-amber-100 text-amber-700"
                    true -> "bg-red-100 text-red-700"
                  end}>
                    <%= if day.mood, do: day.mood, else: "—" %>
                  </div>
                <% end %>
              </div>
              <div class="text-xs text-neutral-400 mb-3">Mood</div>

              <!-- Check-in row -->
              <div class="grid grid-cols-7 gap-1 mb-1">
                <%= for day <- @weekly_history do %>
                  <div class={"h-8 rounded flex items-center justify-center text-xs " <> if(day.checkin, do: "bg-green-100 text-green-700", else: "bg-neutral-100 text-neutral-400")}>
                    <%= if day.checkin, do: "✓", else: "—" %>
                  </div>
                <% end %>
              </div>
              <div class="text-xs text-neutral-400">Check-in</div>
            </div>
          <% end %>
        </div>
      </main>

      <!-- Flash Messages -->
      <div id="flash-container" class="fixed bottom-4 left-4 right-4 max-w-md mx-auto z-50">
        <%= if Phoenix.Flash.get(@flash, :info) do %>
          <div class="p-4 rounded-lg bg-neutral-900 text-white text-sm flex justify-between items-center"
               phx-click={JS.push("lv:clear-flash", value: %{key: "info"}) |> JS.hide(to: "#flash-info")}>
            <span><%= Phoenix.Flash.get(@flash, :info) %></span>
            <button class="ml-4 opacity-70 hover:opacity-100">×</button>
          </div>
        <% end %>
        <%= if Phoenix.Flash.get(@flash, :error) do %>
          <div class="p-4 rounded-lg bg-red-600 text-white text-sm flex justify-between items-center"
               phx-click={JS.push("lv:clear-flash", value: %{key: "error"}) |> JS.hide(to: "#flash-error")}>
            <span><%= Phoenix.Flash.get(@flash, :error) %></span>
            <button class="ml-4 opacity-70 hover:opacity-100">×</button>
          </div>
        <% end %>
      </div>

      <!-- Modals -->
      <%= if @show_meds_modal do %>
        <.modal title="Log Medication" on_close="close_modal">
          <% meds = @data.medication_status %>
          <!-- Current Status -->
          <div class="p-4 rounded-lg bg-neutral-100 mb-4">
            <div class="flex justify-between items-center">
              <div>
                <div class="text-xs text-neutral-500">Today</div>
                <div class="text-xl font-bold"><%= meds.pills_taken_today %> / <%= meds.pills_max_allowed %></div>
              </div>
              <div class="text-right">
                <div class="text-xs text-neutral-500">Remaining</div>
                <div class="text-xl font-bold"><%= meds.pills_remaining %></div>
              </div>
            </div>
            <%= case meds.taper_status do %>
              <% {:tapering, days} -> %>
                <div class="mt-2 text-xs text-neutral-500">
                  <%= days %> days until max <%= meds.pills_prescribed %>/day
                </div>
              <% _ -> %>
            <% end %>
          </div>

          <%= if meds.at_limit do %>
            <div class="p-4 rounded-lg bg-amber-50 border border-amber-200 mb-4">
              <div class="text-sm font-medium text-amber-900">You've reached your limit for today</div>
              <p class="text-xs text-amber-700 mt-1">
                <%= if meds.over_limit, do: "Over limit - no judgment, just tracking.", else: "Can you wait until tomorrow?" %>
              </p>
            </div>
          <% end %>

          <.form for={%{}} phx-submit="save_meds" id="meds-form">
            <div class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Pills</label>
                <div class="flex gap-2">
                  <%= for i <- 1..3 do %>
                    <label class="flex-1">
                      <input type="radio" name="pills_taken" value={i} class="peer hidden" {if i == 1, do: [checked: true], else: []} />
                      <div class={"p-3 text-center text-lg font-bold rounded-lg border-2 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900 " <> if(meds.pills_taken_today + i > meds.pills_max_allowed, do: "opacity-40 border-neutral-200", else: "border-neutral-200 hover:border-neutral-300")}>
                        <%= i %>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">How are you feeling? (1-5)</label>
                <div class="flex gap-2">
                  <%= for i <- 1..5 do %>
                    <label class="flex-1">
                      <input type="radio" name="feeling_before" value={i} class="peer hidden" />
                      <div class="p-2 text-center font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900 hover:border-neutral-300">
                        <%= i %>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Reason</label>
                <select name="trigger" class="w-full p-3 rounded-lg border-2 border-neutral-200 bg-white">
                  <option value="">Just my dose</option>
                  <option value="stress">Stress</option>
                  <option value="work">Work deadline</option>
                  <option value="boredom">Boredom</option>
                  <option value="anxiety">Anxiety</option>
                  <option value="social">Social event</option>
                </select>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Notes</label>
                <textarea name="notes" class="w-full p-3 rounded-lg border-2 border-neutral-200 h-20" placeholder="Optional..."></textarea>
              </div>
            </div>

            <div class="flex gap-3 mt-6">
              <button type="button" class="flex-1 p-3 rounded-lg border-2 border-neutral-200 font-medium hover:bg-neutral-50 transition-colors" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="flex-1 p-3 rounded-lg bg-neutral-900 text-white font-medium hover:bg-neutral-800 transition-colors">
                Log
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>

      <%= if @show_mood_modal do %>
        <.modal title="Quick Mood" on_close="close_modal">
          <.form for={%{}} phx-submit="save_mood" id="mood-form">
            <div class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Mood (1-5)</label>
                <div class="flex gap-2">
                  <%= for i <- 1..5 do %>
                    <label class="flex-1">
                      <input type="radio" name="mood" value={i} class="peer hidden" required />
                      <div class="p-3 text-center text-lg font-bold rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900 hover:border-neutral-300">
                        <%= i %>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Energy (1-5)</label>
                <div class="flex gap-2">
                  <%= for i <- 1..5 do %>
                    <label class="flex-1">
                      <input type="radio" name="energy" value={i} class="peer hidden" />
                      <div class="p-2 text-center font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900 hover:border-neutral-300">
                        <%= i %>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Job dread (1-10)</label>
                <input type="range" name="job_dread" min="1" max="10" value="5" class="w-full" />
                <div class="flex justify-between text-xs text-neutral-400 mt-1">
                  <span>Fine</span>
                  <span>Dreading</span>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Grateful for</label>
                <input type="text" name="gratitude" class="w-full p-3 rounded-lg border-2 border-neutral-200" placeholder="Something small..." />
              </div>
            </div>

            <div class="flex gap-3 mt-6">
              <button type="button" class="flex-1 p-3 rounded-lg border-2 border-neutral-200 font-medium hover:bg-neutral-50 transition-colors" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="flex-1 p-3 rounded-lg bg-neutral-900 text-white font-medium hover:bg-neutral-800 transition-colors">
                Save
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>


      <%= if @show_social_modal do %>
        <.modal title="Log Social" on_close="close_modal">
          <.form for={%{}} phx-submit="save_social" id="social-form">
            <div class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Type</label>
                <div class="grid grid-cols-3 gap-2">
                  <%= for {type, label} <- [{"call", "Call"}, {"text", "Text"}, {"in_person", "In person"}, {"video", "Video"}, {"voice_message", "Voice msg"}] do %>
                    <label>
                      <input type="radio" name="interaction_type" value={type} class="peer hidden" required />
                      <div class="p-3 text-center text-xs font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900 hover:border-neutral-300">
                        <%= label %>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Duration (minutes)</label>
                <input type="number" name="duration_minutes" class="w-full p-3 rounded-lg border-2 border-neutral-200" placeholder="30" />
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Quality (1-5)</label>
                <div class="flex gap-2">
                  <%= for i <- 1..5 do %>
                    <label class="flex-1">
                      <input type="radio" name="quality" value={i} class="peer hidden" />
                      <div class="p-2 text-center font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900 hover:border-neutral-300">
                        <%= i %>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>

              <label class="flex items-center gap-3 cursor-pointer p-3 rounded-lg border-2 border-neutral-200 hover:border-neutral-300">
                <input type="checkbox" name="left_house" value="true" class="w-5 h-5 rounded" />
                <span class="text-sm font-medium">Left apartment for this</span>
              </label>
            </div>

            <div class="flex gap-3 mt-6">
              <button type="button" class="flex-1 p-3 rounded-lg border-2 border-neutral-200 font-medium hover:bg-neutral-50 transition-colors" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="flex-1 p-3 rounded-lg bg-neutral-900 text-white font-medium hover:bg-neutral-800 transition-colors">
                Save
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>

      <%= if @show_checkin_modal do %>
        <.modal title="Daily Check-in" on_close="close_modal" wide={true}>
          <.form for={%{}} phx-submit="save_checkin" id="checkin-form">
            <div class="space-y-6">
              <!-- Medication -->
              <div class="p-4 rounded-lg bg-neutral-50">
                <div class="text-xs font-medium text-neutral-500 mb-3">Medication</div>
                <label class="flex items-center gap-3 cursor-pointer">
                  <input type="checkbox" name="meds_taken_as_prescribed" value="true" class="w-5 h-5 rounded"
                         checked={@data.today_checkin && @data.today_checkin.meds_taken_as_prescribed} />
                  <span class="text-sm">Took meds as prescribed</span>
                </label>
              </div>

              <!-- Job -->
              <div class="p-4 rounded-lg bg-neutral-50">
                <div class="text-xs font-medium text-neutral-500 mb-3">Job</div>
                <div class="space-y-3">
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Dread level (1-10)</label>
                    <input type="range" name="job_dread_level" min="1" max="10" value={(@data.today_checkin && @data.today_checkin.job_dread_level) || 5} class="w-full" />
                  </div>
                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <label class="text-sm text-neutral-600 block mb-1">Jobs applied</label>
                      <input type="number" name="applied_to_jobs" class="w-full p-2 rounded-lg border border-neutral-200" value={@data.today_checkin && @data.today_checkin.applied_to_jobs} />
                    </div>
                    <div>
                      <label class="text-sm text-neutral-600 block mb-1">Search minutes</label>
                      <input type="number" name="job_search_minutes" class="w-full p-2 rounded-lg border border-neutral-200" value={@data.today_checkin && @data.today_checkin.job_search_minutes} />
                    </div>
                  </div>
                </div>
              </div>

              <!-- Money -->
              <div class="p-4 rounded-lg bg-neutral-50">
                <div class="text-xs font-medium text-neutral-500 mb-3">Money</div>
                <div class="space-y-3">
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Unnecessary spending (zł)</label>
                    <input type="number" step="0.01" name="unnecessary_spending" class="w-full p-2 rounded-lg border border-neutral-200" placeholder="0" />
                  </div>
                  <label class="flex items-center gap-3 cursor-pointer">
                    <input type="checkbox" name="debt_payment_made" value="true" class="w-5 h-5 rounded" />
                    <span class="text-sm">Made a debt payment</span>
                  </label>
                </div>
              </div>

              <!-- Social -->
              <div class="p-4 rounded-lg bg-neutral-50">
                <div class="text-xs font-medium text-neutral-500 mb-3">Social</div>
                <div class="space-y-3">
                  <label class="flex items-center gap-3 cursor-pointer">
                    <input type="checkbox" name="talked_to_friend" value="true" class="w-5 h-5 rounded" />
                    <span class="text-sm">Talked to a friend (not just texted)</span>
                  </label>
                  <label class="flex items-center gap-3 cursor-pointer">
                    <input type="checkbox" name="left_apartment" value="true" class="w-5 h-5 rounded" />
                    <span class="text-sm">Left apartment</span>
                  </label>
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Loneliness (1-10)</label>
                    <input type="range" name="loneliness_level" min="1" max="10" value="5" class="w-full" />
                  </div>
                </div>
              </div>

              <!-- Reflection -->
              <div class="p-4 rounded-lg bg-neutral-50">
                <div class="text-xs font-medium text-neutral-500 mb-3">Reflection</div>
                <div class="space-y-3">
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Small win today</label>
                    <input type="text" name="small_win" class="w-full p-2 rounded-lg border border-neutral-200"
                           placeholder="Anything counts..."
                           value={@data.today_checkin && @data.today_checkin.small_win} />
                  </div>
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Biggest struggle</label>
                    <input type="text" name="biggest_struggle" class="w-full p-2 rounded-lg border border-neutral-200"
                           value={@data.today_checkin && @data.today_checkin.biggest_struggle} />
                  </div>
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Tomorrow's intention</label>
                    <input type="text" name="tomorrow_intention" class="w-full p-2 rounded-lg border border-neutral-200"
                           placeholder="One thing..."
                           value={@data.today_checkin && @data.today_checkin.tomorrow_intention} />
                  </div>
                  <div>
                    <label class="text-sm text-neutral-600 block mb-1">Day rating (1-10)</label>
                    <input type="range" name="overall_day_rating" min="1" max="10" value={(@data.today_checkin && @data.today_checkin.overall_day_rating) || 5} class="w-full" />
                  </div>
                </div>
              </div>
            </div>

            <div class="flex gap-3 mt-6">
              <button type="button" class="flex-1 p-3 rounded-lg border-2 border-neutral-200 font-medium hover:bg-neutral-50 transition-colors" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="flex-1 p-3 rounded-lg bg-neutral-900 text-white font-medium hover:bg-neutral-800 transition-colors">
                Complete
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>

      <%= if @show_payment_modal do %>
        <.modal title="Make Payment" on_close="close_modal">
          <.form for={%{}} phx-submit="save_payment" id="payment-form">
            <input type="hidden" name="debt_id" value={@selected_debt_id} />

            <div class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Amount (zł)</label>
                <input type="number" step="0.01" name="amount" class="w-full p-3 rounded-lg border-2 border-neutral-200" required />
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Type</label>
                <div class="flex gap-2">
                  <label class="flex-1">
                    <input type="radio" name="payment_type" value="regular" class="peer hidden" checked />
                    <div class="p-3 text-center text-sm font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900">
                      Regular
                    </div>
                  </label>
                  <label class="flex-1">
                    <input type="radio" name="payment_type" value="extra" class="peer hidden" />
                    <div class="p-3 text-center text-sm font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900">
                      Extra
                    </div>
                  </label>
                  <label class="flex-1">
                    <input type="radio" name="payment_type" value="windfall" class="peer hidden" />
                    <div class="p-3 text-center text-sm font-medium rounded-lg border-2 border-neutral-200 cursor-pointer transition-all peer-checked:bg-neutral-900 peer-checked:text-white peer-checked:border-neutral-900">
                      Windfall
                    </div>
                  </label>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-neutral-500 mb-2">Source (optional)</label>
                <input type="text" name="source" class="w-full p-3 rounded-lg border-2 border-neutral-200" placeholder="Where from?" />
              </div>
            </div>

            <div class="flex gap-3 mt-6">
              <button type="button" class="flex-1 p-3 rounded-lg border-2 border-neutral-200 font-medium hover:bg-neutral-50 transition-colors" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="flex-1 p-3 rounded-lg bg-neutral-900 text-white font-medium hover:bg-neutral-800 transition-colors">
                Save
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>
    </div>
    """
  end

  # ============================================
  # MODAL COMPONENT
  # ============================================

  attr :title, :string, required: true
  attr :on_close, :string, required: true
  attr :wide, :boolean, default: false
  slot :inner_block, required: true

  defp modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4" phx-window-keydown="close_modal" phx-key="escape">
      <div class="fixed inset-0 bg-black/50" phx-click={@on_close}></div>
      <div class={"relative bg-white rounded-xl w-full max-h-[90vh] overflow-y-auto shadow-xl " <> if(@wide, do: "max-w-xl", else: "max-w-md")}>
        <div class="p-4 border-b border-neutral-200 flex justify-between items-center sticky top-0 bg-white rounded-t-xl">
          <h3 class="text-lg font-semibold"><%= @title %></h3>
          <button class="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-neutral-100 transition-colors"
                  phx-click={@on_close}>
            ×
          </button>
        </div>
        <div class="p-4">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  # ============================================
  # EVENT HANDLERS
  # ============================================

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, close_all_modals(socket)}
  end

  @impl true
  def handle_event("log_meds", _, socket) do
    {:noreply, socket
      |> close_all_modals()
      |> assign(:show_meds_modal, true)
      |> assign(:show_meds_reminder, false)}
  end

  @impl true
  def handle_event("log_mood", _, socket) do
    {:noreply, socket |> close_all_modals() |> assign(:show_mood_modal, true)}
  end

  @impl true
  def handle_event("log_social", _, socket) do
    {:noreply, socket
      |> close_all_modals()
      |> assign(:show_social_modal, true)
      |> assign(:show_social_reminder, false)}
  end

  @impl true
  def handle_event("dismiss_meds_reminder", _, socket) do
    reminder_key = "meds_#{Date.utc_today()}"
    dismissed = MapSet.put(socket.assigns.dismissed_reminders, reminder_key)

    {:noreply, socket
      |> assign(:show_meds_reminder, false)
      |> assign(:dismissed_reminders, dismissed)}
  end

  @impl true
  def handle_event("dismiss_social_reminder", _, socket) do
    reminder_key = "social_#{Date.utc_today()}"
    dismissed = MapSet.put(socket.assigns.dismissed_reminders, reminder_key)

    {:noreply, socket
      |> assign(:show_social_reminder, false)
      |> assign(:dismissed_reminders, dismissed)}
  end

  @impl true
  def handle_event("show_debt_section", _, socket) do
    # For now, just show payment modal for first debt if exists
    case socket.assigns.data.debts do
      [debt | _] ->
        {:noreply, socket
          |> close_all_modals()
          |> assign(:show_payment_modal, true)
          |> assign(:selected_debt_id, debt.id)
        }
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_checkin", _, socket) do
    {:noreply, socket |> close_all_modals() |> assign(:show_checkin_modal, true)}
  end

  @impl true
  def handle_event("toggle_history", _, socket) do
    show = not socket.assigns.show_history
    weekly_history = if show, do: LifeReboot.get_weekly_history(), else: []

    {:noreply, socket
      |> assign(:show_history, show)
      |> assign(:weekly_history, weekly_history)}
  end

  @impl true
  def handle_event("make_payment", %{"id" => debt_id}, socket) do
    {:noreply, socket
      |> close_all_modals()
      |> assign(:show_payment_modal, true)
      |> assign(:selected_debt_id, debt_id)
    }
  end

  @impl true
  def handle_event("save_meds", params, socket) do
    pills = String.to_integer(params["pills_taken"] || "1")

    attrs = %{
      "taken_at" => DateTime.utc_now(),
      "pills_taken" => pills,
      "feeling_before" => params["feeling_before"],
      "trigger" => if(params["trigger"] == "", do: nil, else: params["trigger"]),
      "notes" => params["notes"]
    }

    case LifeReboot.create_medication_log(attrs) do
      {:ok, _log} ->
        meds = LifeReboot.get_medication_status()
        message = cond do
          meds.over_limit -> "Logged. You're over your limit - no judgment, just tracking."
          meds.at_limit -> "Logged. You've hit your limit for today."
          true -> "Logged. #{meds.pills_remaining} remaining today."
        end

        {:noreply, socket
          |> close_all_modals()
          |> load_dashboard_data()
          |> put_flash(:info, message)
        }
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error saving")}
    end
  end

  @impl true
  def handle_event("save_mood", params, socket) do
    attrs = %{
      "logged_at" => DateTime.utc_now(),
      "mood" => params["mood"],
      "energy" => params["energy"],
      "job_dread" => params["job_dread"],
      "gratitude" => params["gratitude"]
    }

    case LifeReboot.create_mood_log(attrs) do
      {:ok, _log} ->
        {:noreply, socket
          |> close_all_modals()
          |> load_dashboard_data()
          |> put_flash(:info, "Mood logged")
        }
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error saving")}
    end
  end

  @impl true
  def handle_event("save_social", params, socket) do
    attrs = %{
      "interacted_at" => DateTime.utc_now(),
      "interaction_type" => params["interaction_type"],
      "duration_minutes" => params["duration_minutes"],
      "quality" => params["quality"],
      "left_house" => params["left_house"] == "true"
    }

    case LifeReboot.create_interaction(attrs) do
      {:ok, _interaction} ->
        {:noreply, socket
          |> close_all_modals()
          |> load_dashboard_data()
          |> put_flash(:info, "Social interaction logged")
        }
      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        {:noreply, put_flash(socket, :error, "Error: #{inspect(errors)}")}
    end
  end

  @impl true
  def handle_event("save_checkin", params, socket) do
    attrs = %{
      "date" => Date.utc_today(),
      "completed_at" => DateTime.utc_now(),
      "meds_taken_as_prescribed" => params["meds_taken_as_prescribed"] == "true",
      "meds_notes" => params["meds_notes"],
      "job_dread_level" => params["job_dread_level"],
      "applied_to_jobs" => params["applied_to_jobs"],
      "job_search_minutes" => params["job_search_minutes"],
      "unnecessary_spending" => params["unnecessary_spending"],
      "debt_payment_made" => params["debt_payment_made"] == "true",
      "talked_to_friend" => params["talked_to_friend"] == "true",
      "left_apartment" => params["left_apartment"] == "true",
      "loneliness_level" => params["loneliness_level"],
      "small_win" => params["small_win"],
      "biggest_struggle" => params["biggest_struggle"],
      "tomorrow_intention" => params["tomorrow_intention"],
      "overall_day_rating" => params["overall_day_rating"]
    }

    case LifeReboot.upsert_honest_checkin(attrs) do
      {:ok, checkin} ->
        message = Rzeczywiscie.LifeReboot.HonestCheckin.encouragement_message(checkin)
        {:noreply, socket
          |> close_all_modals()
          |> load_dashboard_data()
          |> put_flash(:info, message)
        }
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error saving")}
    end
  end

  @impl true
  def handle_event("save_payment", params, socket) do
    debt = LifeReboot.get_debt!(params["debt_id"])

    attrs = %{
      "amount" => params["amount"],
      "paid_at" => DateTime.utc_now(),
      "payment_type" => params["payment_type"],
      "source" => params["source"]
    }

    case LifeReboot.make_debt_payment(debt, attrs) do
      {:ok, {_debt, payment}} ->
        message = Rzeczywiscie.LifeReboot.DebtPayment.celebration_message(payment)
        {:noreply, socket
          |> close_all_modals()
          |> load_dashboard_data()
          |> put_flash(:info, message)
        }
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error saving")}
    end
  end

  @impl true
  def handle_info({_event, _payload}, socket) do
    if any_modal_open?(socket) do
      {:noreply, socket}
    else
      {:noreply, load_dashboard_data(socket)}
    end
  end

  # Reminder: check meds
  @impl true
  def handle_info(:check_meds_reminder, socket) do
    schedule_next_reminder()

    data = socket.assigns.data
    reminder_key = "meds_#{Date.utc_today()}"

    socket =
      if not data.took_meds_today and
         not MapSet.member?(socket.assigns.dismissed_reminders, reminder_key) do
        socket
        |> assign(:show_meds_reminder, true)
        |> assign(:reminder_message, meds_reminder_message())
      else
        socket
      end

    {:noreply, socket}
  end

  # Reminder: social check
  @impl true
  def handle_info(:check_social_reminder, socket) do
    # Schedule next check in 6 hours
    Process.send_after(self(), :check_social_reminder, :timer.hours(6))

    data = socket.assigns.data
    days = data.days_since_any_interaction
    reminder_key = "social_#{Date.utc_today()}"

    socket =
      if days != nil and days >= @social_reminder_days and
         not MapSet.member?(socket.assigns.dismissed_reminders, reminder_key) do
        socket
        |> assign(:show_social_reminder, true)
        |> assign(:social_reminder_message, social_reminder_message(days))
      else
        socket
      end

    {:noreply, socket}
  end

  # ============================================
  # HELPERS
  # ============================================

  defp schedule_reminders do
    # Check meds reminder every hour
    Process.send_after(self(), :check_meds_reminder, :timer.seconds(5))
    # Check social reminder
    Process.send_after(self(), :check_social_reminder, :timer.seconds(10))
  end

  defp schedule_next_reminder do
    # Check again in 1 hour
    Process.send_after(self(), :check_meds_reminder, :timer.hours(1))
  end

  defp meds_reminder_message do
    hour = DateTime.utc_now().hour
    cond do
      hour < 12 -> "Morning reminder: have you taken your meds?"
      hour < 17 -> "Afternoon check: meds taken today?"
      hour < 21 -> "Evening reminder: don't forget your meds"
      true -> "Late night: still time to take your meds if needed"
    end
  end

  defp social_reminder_message(days) do
    cond do
      days >= 7 -> "It's been #{days} days. Even a quick text counts."
      days >= 5 -> "#{days} days since you talked to someone. Reach out?"
      true -> "Been a few days. Maybe message someone?"
    end
  end

  defp load_dashboard_data(socket) do
    show_history = Map.get(socket.assigns, :show_history, false)

    socket
    |> assign(:data, LifeReboot.get_life_dashboard_data())
    |> assign(:show_meds_modal, Map.get(socket.assigns, :show_meds_modal, false))
    |> assign(:show_mood_modal, Map.get(socket.assigns, :show_mood_modal, false))
    |> assign(:show_social_modal, Map.get(socket.assigns, :show_social_modal, false))
    |> assign(:show_checkin_modal, Map.get(socket.assigns, :show_checkin_modal, false))
    |> assign(:show_payment_modal, Map.get(socket.assigns, :show_payment_modal, false))
    |> assign(:selected_debt_id, Map.get(socket.assigns, :selected_debt_id, nil))
    |> assign(:dismissed_reminders, Map.get(socket.assigns, :dismissed_reminders, MapSet.new()))
    |> assign(:show_history, show_history)
    |> assign(:weekly_history, if(show_history, do: LifeReboot.get_weekly_history(), else: []))
  end

  defp close_all_modals(socket) do
    socket
    |> assign(:show_meds_modal, false)
    |> assign(:show_mood_modal, false)
    |> assign(:show_social_modal, false)
    |> assign(:show_checkin_modal, false)
    |> assign(:show_payment_modal, false)
  end

  defp any_modal_open?(socket) do
    socket.assigns[:show_meds_modal] ||
    socket.assigns[:show_mood_modal] ||
    socket.assigns[:show_social_modal] ||
    socket.assigns[:show_checkin_modal] ||
    socket.assigns[:show_payment_modal]
  end

  defp format_currency(amount) when is_struct(amount, Decimal) do
    "#{Decimal.round(amount, 0)} zł"
  end
  defp format_currency(_), do: "0 zł"

  defp encouragement_message(data) do
    score = calculate_day_score(data)
    cond do
      score >= 80 -> "You're doing amazing today."
      score >= 60 -> "Great progress. Keep going."
      score >= 40 -> "Solid effort. Every step counts."
      score >= 20 -> "You showed up. That matters."
      true -> "It's okay to have tough days."
    end
  end

  defp calculate_day_score(data) do
    scores = [
      if(data.took_meds_today, do: 30, else: 0),
      if(data.days_since_any_interaction != nil and data.days_since_any_interaction < 3, do: 25, else: 0),
      if(data.today_checkin && data.today_checkin.completed_at, do: 25, else: 0),
      if(data.debt_stats.progress_percent > 0, do: 20, else: 0)
    ]
    Enum.sum(scores)
  end
end
