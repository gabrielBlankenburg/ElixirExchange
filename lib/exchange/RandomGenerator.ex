defmodule Exchange.RandomGenerator do
	@moduledoc """
	A bot to generate orders to a worker of type `Exchange.Trade` randomly, based on the `Exchange.Trade`
	current price. In a given interval it will clear orders keeping only the n top orders, else it may have
	a lot of old orders that is most likely to never get reached (like an sell order of 20,000 while the price is 10).
	The parameters are available on the `options()`.
	@TODO Generate some validators, like don't allow generating order with a value <= 0.
	"""
	use GenServer
	alias Exchange.Trade

	@typedoc """
	`frequency` is the interval in miliseconds that the worker will generate and send orders. Default is `500`.
	`min_variance` is a percentage that will stablish the minimum value of the order, based on the current price.
	eg: if a price is 100 and the min_variance is 0.1, the minimum value of the next order will at least 90 (100 - (100 * 0.1)).
	Default is `0.05`.
	`max_variance` uses the same logic as the `min_variance`, but setting it to the maximum order value. Default is `0.05`
	`min_order_amount` is the minimum amount of shares for an order. Default is `10`
	`min_order_amount` is the maximum amount of shares for an order. Default is `100`
	`min_volume` is the minimum amount of orders by frequency. Default is `10`
	`max_volume` is the maximum amount of orders by frequency. Default is: `100`
	`amount_keep_orders` the amount of orders kept when clears the orders. Default is `1000`.
	`clear_orders_frequency` is the frequency in miliseconds to clear the orders. Default is `5000`.
	"""
	@type options :: [
		frequency: integer() | nil,
		min_variance: float() | nil,
		max_variance: float() | nil,
		min_order_amount: float() | nil,
		max_order_amount: float() | nil,
		min_volume: integer() | nil,
		max_volume: integer() | nil,
		amount_keep_orders: integer() | nil,
		clear_orders_frequency: integer() | nil
	]

	@default_frequency 500
	@default_price_variance 0.05
	@default_min_order_amount 10
	@default_max_order_amount 100
	@default_min_volume 10
	@default_max_volume 100
	@default_amount_keep_orders 200
	@default_clear_orders_frequency 3000

	@doc """
	Receives the id of the currency, which action will be made and the `options()`.
	"""
	@spec start_link(atom() | pid(), :sell | :buy, options()) :: GenServer.on_start()
	def start_link(currency, action, opts \\ []) when action in [:buy, :sell] do
		args = %{
			currency: currency,
			action: action,
			frequency: get_init_opts(opts, :frequency),
			min_variance: get_init_opts(opts, :min_variance),
			max_variance: get_init_opts(opts, :max_variance),
			min_order_amount: get_init_opts(opts, :min_order_amount),
			max_order_amount: get_init_opts(opts, :max_order_amount),
			min_volume: get_init_opts(opts, :min_volume),
			max_volume: get_init_opts(opts, :max_volume),
			amount_keep_orders: get_init_opts(opts, :amount_keep_orders),
			clear_orders_frequency: get_init_opts(opts, :clear_orders_frequency)
		}

		GenServer.start_link(__MODULE__, args)
	end

	@doc """
	Used to set some options from `options()`.
	"""
	@spec set_option(pid(), atom(), any()) :: :ok
	def set_option(pid, option, value) do
		GenServer.cast(pid, {:set_option, option, value})
	end

	@spec get_state(pid()) :: map()
	def get_state(pid) do
		GenServer.call(pid, :get_state)
	end

	# Used to get the given option or return its default value.
	defp get_init_opts(opts, key) do
		case {opts[key], key} do
			{nil, :frequency} -> @default_frequency
			{nil, :min_variance} -> @default_price_variance
			{nil, :max_variance} -> @default_price_variance
			{nil, :min_order_amount} -> @default_min_order_amount
			{nil, :max_order_amount} -> @default_max_order_amount
			{nil, :min_volume} -> @default_min_volume
			{nil, :max_volume} -> @default_max_volume
			{nil, :amount_keep_orders} -> @default_amount_keep_orders
			{nil, :clear_orders_frequency} -> @default_clear_orders_frequency
			{value, _} -> value
		end
	end

	@impl true
	def init(state) do
		send(self(), :generate_orders)
		send(self(), :clear_orders)

		{:ok, state}
	end


	#Generates the random orders following the state parameters in the given frequency.
	@impl true
	def handle_info(:generate_orders, state) do
		state
			|> generate_orders
			|> Enum.each(&make_order/1)

		Process.send_after(self(), :generate_orders, state[:frequency])

		{:noreply, state}
	end

	#Keeps only the most n recent orders in the given time, if this parameter is set to `nil` it won't
	#ever clear the orders.
	def handle_info(:clear_orders, %{clear_orders_frequency: nil} = state) do
		{:noreply, state}
	end

	def handle_info(
		:clear_orders,
		state
	) do
		Trade.keep_only_last_n_orders(state[:currency], state[:action], state[:amount_keep_orders])

		Process.send_after(self(), :clear_orders, state[:clear_orders_frequency])

		{:noreply, state}
	end

	@impl true
	def handle_cast({:set_option, option, value}, state) do
		if option == :clear_orders_frequency and value != nil, do: send(self(), :clear_orders)

		{:noreply, Map.put(state, option, value)}
	end

	@impl true
	def handle_call(:get_state, _from, state) do
		{:reply, state, state}
	end

	defp make_order(%{pid: pid, action: action, value: value, amount: amount}) do
		Trade.make_order(pid, action, value, amount)
	end

	# Gets the price and the number of orders that will be sent and generates the order.
	defp generate_orders(state) do
		price = Trade.get_price(state[:currency])

		state[:min_volume]
			|> random_float(state[:max_volume])
			|> trunc
			|> generate_orders(price, state)
	end

	# Generates the orders with random prices based on the given price (and the args variances)
	defp generate_orders(amount, price, state) do
		1..amount
			|> Enum.map(fn _ -> generate_order_args(state, price) end)
	end

	# Generates a random price and amount (of shares)
	defp generate_order_args(state, current_price) do
		price =
			current_price
			|> generate_random_price(
				min_variance: state[:min_variance],
				max_variance: state[:max_variance])

		amount =
			state[:min_order_amount]
			|> random_float(state[:max_order_amount])
			|> trunc

		%{
			pid: state[:currency],
			action: state[:action],
			value: price,
			amount: amount
		}
	end

	defp generate_random_price(value, opts) do
		min_variance = opts[:min_variance]
		max_variance = opts[:max_variance]

		min = value - (value * min_variance)
		max = value * (1 + max_variance)

		min
			|>random_float(max)
			|> :erlang.float_to_binary([decimals: 2])
			|> String.to_float
	end

	defp random_float(a, b) do
		a + :rand.uniform() * (b-a)
	end
end
