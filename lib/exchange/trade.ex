defmodule Exchange.Trade do
  @moduledoc """
  A Server to handle orders and keep the price history.
  """
	use GenServer

  @type price :: %{date: %DateTime{}, value: float()}
  @type order :: %{value: float(), amount: integer()}

  @spec start_link(%{currency: atom(), prices: list(price())}) :: GenServer.on_start()
  def start_link(%{currency: name} = args) do
    GenServer.start(__MODULE__, args, name: name)
  end

  @doc """
  Creates an order
  """
  @spec make_order(pid(), :buy | :sell, float(), integer()) :: :ok
  def make_order(pid, action, value, amount) when action in [:buy, :sell] do
    order = %{value: value, amount: amount}

    GenServer.cast(pid, {action, order})
  end

  @doc """
  Get the order list in a `tuple` `{buy_orders, sell_orders}` sorted by the orders buy orders higher to lower
  and sell orders lower to highers
  """
  @spec get_orders(pid() | atom()) :: {list(order), list(order)}
  def get_orders(pid) do
    GenServer.call(pid, :get_orders)
  end

  @doc """
  Get top n orders for the given action.
  """
  @spec get_orders(pid() | atom(), :buy | :sell, integer()) :: list(order())
  def get_orders(pid, action, limit \\ 5) when action in [:buy, :sell] do
    pid
      |> GenServer.call({:get_orders, action})
      |> Enum.take(limit)
  end

  @spec get_price(atom() | pid()) :: float()
  def get_price(pid) do
    GenServer.call(pid, :get_price)
  end

  @doc """
  Clears all orders.
  """
  @spec clear_orders(pid() | atom()) :: :ok
  def clear_orders(pid) do
    GenServer.cast(pid, :clear_orders)
  end

  @doc """
  Clear every for the given `action` (`:buy` or `:sell`) but the top `amount`.
  """
  @spec keep_only_last_n_orders(pid() | atom(), :buy | :sell, integer()) :: :ok
  def keep_only_last_n_orders(pid, action, amount) do
    GenServer.cast(pid, {:keep_only_last_n_orders, action, amount})
  end

  @impl true
  def init(%{currency: _, prices: _} = data) do
    state = {data, {[], []}}

    {:ok, state}
  end

  @impl true
  # Sets the state, it is used when there is a new order, on new orders, for the sorting
  # and recursive refresh status, it can halt the message for too long, so instead of halting
  # it delegates this responsability to another process, that sends a message back to this server
  def handle_info({:set_state, state}, _) do
    {:noreply, state}
  end

  @impl true
  # Adds a buy order to the queue, sorting the orders by the preferred sequence (higher buy orders to lower)
  def handle_cast({:buy, value}, {data, {buy, sell}} = state) do
    handle_order(data, [value | buy], sell)
    {:noreply, state}
  end

  # Adds a sell order to the queue, sorting the orders by the preferred sequence (lower sell orders to higher)
  def handle_cast({:sell, value}, {data, {buy, sell}} = state) do
    handle_order(data, buy, [value | sell])

    {:noreply, state}
  end

  def handle_cast(:clear_orders, {data, {_, _}}) do
    {:noreply, {data, {[], []}}}
  end

  def handle_cast({:keep_only_last_n_orders, :buy, amount}, {data, {buys, sells}}) do
    case Enum.split(buys, amount) do
      {new_buys, []} -> {:noreply, {data, {new_buys, sells}}}
      {_, new_buys} -> {:noreply, {data, {new_buys, sells}}}
    end
  end

  def handle_cast({:keep_only_last_n_orders, :sell, amount}, {data, {buys, sells}}) do
    case Enum.split(sells, amount) do
      {new_sells, []} -> {:noreply, {data, {buys, new_sells}}}
      {_, new_sells} -> {:noreply, {data, {buys, new_sells}}}
    end
  end

  @impl true
  def handle_call(:get_orders, _from, {data, offers}) do
    {:reply, offers, {data, offers}}
  end

  def handle_call({:get_orders, :buy}, _from, {data, {buy, sell}}) do
    {:reply, buy, {data, {buy, sell}}}
  end

  def handle_call({:get_orders, :sell}, _from, {data, {buy, sell}}) do
    {:reply, sell, {data, {buy, sell}}}
  end

  def handle_call(:get_price, _from, {%{prices: [%{value: price} | _]}, _} = state) do
    {:reply, price, state}
  end

  # Sort the orders and return the new state
  defp handle_order(data, buy, sell) do
    caller = self()

    spawn(fn ->
      {buys, sells} = sort_orders(buy, sell)

      state = handle_orders(data, buys, sells)

      send(caller, {:set_state, state})
    end)

    # {data, orders}
  end

  # If there is a deal to be done, it refreshes the price (the sell value) and refreshes the orders
  # removing the amount sold from both orders, if any order had less than the demanded, they are removed
  # from the order list and the next order is compared. It is made recursively untill there is no valid
  # deal. Returns the new state
  defp handle_orders(
    %{prices: prices} = data,
    [%{value: buy_value} | _] = buys,
    [%{value: sell_value} | _] = sells
  ) when buy_value >= sell_value do
    price = %{date: DateTime.now!("Etc/UTC"), value: sell_value}

    new_data = Map.put(data, :prices, [price | prices])

    orders = handle_after_deal(buys, sells)

    {new_data, orders}
  end

  # If there is no valid deal, it just return the state as it curently is.
  defp handle_orders(data, buy, sell), do: {data, {buy, sell}}

  # Refreshes the amount of each order from the last deal, if it's 0 or less it is removed from the list.
  defp handle_after_deal([
    %{amount: buy_amount} | tail_buy],
    [%{amount: sell_amount} | tail_sell]
  ) when buy_amount == sell_amount, do: {tail_buy, tail_sell}

  defp handle_after_deal([
    %{amount: buy_amount} = top_buy | tail_buy],
    [%{amount: sell_amount} | tail_sell]
  ) when buy_amount > sell_amount do
    new_buy = Map.put(top_buy, :amount, buy_amount - sell_amount)

    {[new_buy | tail_buy], tail_sell}
  end

  defp handle_after_deal([
    %{amount: buy_amount} | tail_buy],
    [%{amount: sell_amount} = top_sell | tail_sell]
  ) do
    new_sell = Map.put(top_sell, :amount, sell_amount - buy_amount)

    {tail_buy, [new_sell | tail_sell]}
  end

  # Sorts the orders, buy orders if higher to lower and sell orders are lower to higher.
  defp sort_orders(buy, sell) do
    buy = Enum.sort(buy, &(&1[:value] >= &2[:value]))
    sell = Enum.sort(sell, &(&1[:value] <= &2[:value]))

    {buy, sell}
  end
end
