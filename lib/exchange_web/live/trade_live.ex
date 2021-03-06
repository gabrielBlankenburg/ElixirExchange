defmodule ExchangeWeb.TradeLive do
	use Phoenix.LiveView
	# alias ExchangeWeb.Router.Helpers, as: Routes
	alias Exchange.Trade

	@refresh_frequency 100

	@impl true
	def mount(_params, %{"id" => string_id}, socket) do
		# Find a better way to do so, probably by the controller mapping the right atoms
		id = String.to_atom(string_id)

		send(self(), :fetch_orders)

		{:ok, assign(socket, buy_orders: [], sell_orders: [], price: "loading", id: id)}
	end

	@impl true
	def handle_info(:fetch_orders, socket) do
		id = socket.assigns.id

		buy_orders = Trade.get_orders(id, :buy, 10)
		sell_orders = Trade.get_orders(id, :sell, 10)
		price = Trade.get_price(id)

		Process.send_after(self(), :fetch_orders, @refresh_frequency)

		{:noreply, assign(socket, buy_orders: buy_orders, sell_orders: sell_orders, price: price)}
	end
end
