# Exchange

To start your Phoenix server:

- Install dependencies with `mix deps.get`
- Create and migrate your database with `mix ecto.setup`
- Install Node.js dependencies with `npm install` inside the `assets` directory
- Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000/trades`](http://localhost:4000/trades) from your browser.

## About

It is a simulator of how exchange market works, currently there are two workers simulating a currency and two bots for each worker simulating "random" buy and sell orders. The buy and sell orders are created based on the current price of the currency. While running the project you can start new currencies and bots, change their parameters to see the data changing. Check each worker documentation for further details.

You can access [`localhost:4000/trades/e_coin`](http://localhost:4000/trades/e_coin) to check the data changing on real time.

Be careful when changing the parameters of the bots. Since it has no back pressure mechanism yet, milions of bots making request to the same server can take the application down.
