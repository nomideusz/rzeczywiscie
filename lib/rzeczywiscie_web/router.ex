defmodule RzeczywiscieWeb.Router do
  use RzeczywiscieWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RzeczywiscieWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin_auth do
    plug :require_admin_basic_auth
  end

  # BasicAuth against ADMIN_PASSWORD (config :rzeczywiscie, :admin_password).
  # On success a session flag is set; the require_admin on_mount hook checks
  # it so the LiveView websocket mount is protected too.
  defp require_admin_basic_auth(conn, _opts) do
    if get_session(conn, :admin_authed) do
      conn
    else
      expected = Application.get_env(:rzeczywiscie, :admin_password)

      with true <- is_binary(expected) and expected != "",
           {_user, pass} <- Plug.BasicAuth.parse_basic_auth(conn),
           true <- Plug.Crypto.secure_compare(pass, expected) do
        put_session(conn, :admin_authed, true)
      else
        _ ->
          conn
          |> Plug.BasicAuth.request_basic_auth()
          |> halt()
      end
    end
  end

  scope "/", RzeczywiscieWeb do
    pipe_through :browser

    live_session :default, on_mount: {RzeczywiscieWeb.Live.Hooks, :set_current_path} do
      live "/", HomeLive
      live "/example", ExampleLive
      live "/draw", DrawingBoardLive
      live "/kanban", KanbanBoardLive
      live "/counter", PersistentCounterLive
      live "/pixels", PixelCanvasLive
      live "/friends", FriendsLive
      live "/friends/my-photos", UserPhotosLive
      live "/friends/:room", FriendsLive
      live "/real-estate", RealEstateLive
      live "/favorites", FavoritesLive
      live "/stats", StatsLive
      live "/hot-deals", HotDealsLive
      live "/llm-results", LLMResultsLive
      live "/url-inspector", UrlInspectorLive

      # Life Planning Routes (old)
      live "/life-old", LifeDashboardLive
      live "/life-old/projects/:id", LifeProjectLive
      live "/life-old/check-in", LifeCheckinLive
      live "/life-old/weekly-review", WeeklyReviewLive
      live "/life-old/progress", ProgressDashboardLive

      # Life Reboot - Personalized Life Management
      live "/life", LifeRebootLive
    end

    get "/kanban/image/:card_id", KanbanImageController, :show
  end

  scope "/", RzeczywiscieWeb do
    pipe_through [:browser, :admin_auth]

    live_session :admin,
      on_mount: [
        {RzeczywiscieWeb.Live.Hooks, :set_current_path},
        {RzeczywiscieWeb.Live.Hooks, :require_admin}
      ] do
      live "/admin", AdminLive
      live "/friends/admin", FriendsAdminLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", RzeczywiscieWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:rzeczywiscie, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RzeczywiscieWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
