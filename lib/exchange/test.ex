defmodule Exchange.Test do
	use GenServer

	def start_link do
		GenServer.start_link(__MODULE__, "Some State")
	end

	def init(state) do
		send(self(), :halt_message)

		{:ok, state}
	end

	def handle_info(:halt_message, state) do
		:timer.sleep(5000)

		send(self(), :halt_message)

		{:noreply, state}
	end

	def handle_call(:get_state, _from, state) do
		{:reply, state, state}
	end
end
