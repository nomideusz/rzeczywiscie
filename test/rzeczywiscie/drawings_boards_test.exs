defmodule Rzeczywiscie.DrawingsBoardsTest do
  use Rzeczywiscie.DataCase

  alias Rzeczywiscie.{Boards, Drawings}

  describe "drawings" do
    test "strokes persist one row each and replay in insertion order" do
      {:ok, board} = Drawings.get_or_create_board("test-board")

      Drawings.add_stroke(board.id, %{"color" => "#000", "size" => 4, "points" => [[1, 1], [2, 2]]})
      Drawings.add_stroke(board.id, %{"color" => "#f00", "size" => 2, "points" => [[9, 9]]})

      assert [first, second] = Drawings.get_strokes(board.id)
      assert first["color"] == "#000"
      assert second["color"] == "#f00"
    end

    test "broadcast_segment does not echo to the sender" do
      Drawings.subscribe()

      # from another process: we should receive it
      Task.await(Task.async(fn -> Drawings.broadcast_segment(%{x1: 1}) end))
      assert_receive {:draw_segment, %{x1: 1}}

      # from ourselves: we should not
      Drawings.broadcast_segment(%{x1: 2})
      refute_receive {:draw_segment, %{x1: 2}}, 50
    end
  end

  describe "kanban" do
    test "board payload never carries image blobs, only a versioned URL" do
      {:ok, board} = Boards.get_or_create_board("test-kanban")

      Boards.add_card(board.id, %{
        card_id: "img-card",
        text: "with image",
        column: "todo",
        created_by: "test",
        position: 0,
        image_data: "data:image/png;base64,aGVsbG8="
      })

      card = Boards.get_cards(board.id) |> Enum.find(&(&1.id == "img-card"))

      refute Map.has_key?(card, :image_data)
      assert card.image_url =~ "/kanban/image/img-card?v="
      assert Boards.get_card_image("img-card") == "data:image/png;base64,aGVsbG8="
    end
  end
end
