defmodule RzeczywiscieWeb.PixelCanvasLiveTest do
  use RzeczywiscieWeb.ConnCase

  import Phoenix.LiveViewTest

  test "canvas loads, pixel placement round-trips, cooldown enforced", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pixels")

    hook = element(view, "[phx-hook=SvelteHook]")

    # the client pulls initial state once mounted; server replies with the canvas
    render_hook(hook, "load_canvas", %{})
    assert_reply(view, %{pixels: []})

    # place a pixel -> broadcast comes back to this client as a push event
    render_hook(hook, "place_pixel", %{"x" => 3, "y" => 4})
    assert_push_event(view, "pixel", %{x: 3, y: 4})

    # immediate second attempt is on cooldown: no new pixel event
    render_hook(hook, "place_pixel", %{"x" => 9, "y" => 9})
    refute_push_event(view, "pixel", %{x: 9, y: 9})

    # color selection round-trips into props
    [_, second_color | _] = Rzeczywiscie.PixelCanvas.available_colors()
    render_hook(hook, "select_color", %{"color" => second_color})
    assert render(view) =~ "selectedColor"
  end
end
