defmodule ExchangeWeb.TradeController do
	use ExchangeWeb, :controller

	import Phoenix.LiveView.Controller

	def index(conn, _) do
		currencies = mock_currencies()
		render(conn, "index.html", currencies: currencies)
	end

	def show(conn, %{"id" => id}) do
		live_render(conn, ExchangeWeb.TradeLive, session: %{
			"id" => id
		})
	end

	defp mock_currencies do
		[
			%{
				id: :e_coin,
				name: "E-Coin"
			},
			%{
				id: :my_coin,
				name: "My Coin"
			}
		]
	end
end
