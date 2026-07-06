defmodule RzeczywiscieWeb.KanbanImageController do
  use RzeczywiscieWeb, :controller

  # Serves kanban card images (stored as base64 data URLs) over HTTP so the
  # board payload never carries megabytes of base64. URLs are versioned with
  # ?v=updated_at, so aggressive caching is safe.
  def show(conn, %{"card_id" => card_id}) do
    with "data:" <> _ = data_url <- Rzeczywiscie.Boards.get_card_image(card_id),
         [meta, b64] <- String.split(data_url, ",", parts: 2),
         {:ok, binary} <- Base.decode64(b64) do
      content_type =
        meta
        |> String.trim_leading("data:")
        |> String.split(";")
        |> hd()
        |> case do
          "" -> "image/png"
          type -> type
        end

      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_resp(200, binary)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end
end
