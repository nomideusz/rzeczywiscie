defmodule RzeczywiscieWeb.PageController do
  use RzeczywiscieWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
