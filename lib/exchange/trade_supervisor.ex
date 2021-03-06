defmodule Exchange.TradeSupervisor do
	@moduledoc """
	Generates some mocks for the currencies and bots to buy and sell them.
	"""
	use Supervisor

	alias Exchange.Trade
	alias Exchange.RandomGenerator

	def start_link(args) do
		Supervisor.start_link(__MODULE__, args, name: __MODULE__)
	end

	@impl true
	def init(_) do
		currencies = [
			%{name: :e_coin, value: 10.00},
			%{name: :my_coin, value: 50.00}
		]

		currencies_workers = generate_currencies(currencies)

		bots = currencies
			|> Stream.map(fn %{name: name} -> name end)
			|> Enum.map(&generate_bots/1)
			|> List.flatten

		workers = currencies_workers ++ bots

		Supervisor.init(workers, strategy: :one_for_one)
	end

	# generates a currency for each value
	defp generate_currencies(currencies) do
		Enum.map(currencies, fn %{name: name, value: value} ->
			%{
				id: "currency:#{name}",
				start: {
					Trade,
					:start_link,
					[name, value]
				}
			}
		end)
	end

	defp generate_bots(currency) do
		buy = %{
			id: "buy:#{currency}",
			start: {
				RandomGenerator,
				:start_link,
				[currency, :buy]
			}
		}

		sell = %{
			id: "sell:#{currency}",
			start: {
				RandomGenerator,
				:start_link,
				[currency, :sell]
			}
		}

		[buy, sell]
	end
end
