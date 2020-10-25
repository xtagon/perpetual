# Perpetual

Perpetual is a simple abstraction around repeatedly iterating state in Elixir.

It is similar to Elixir's `Agent` module in that it can share or store state
that must be accessed from different processes or by the same process at
different points in time, and in additiion to that, `Perpetual` lets you
define a function for repeatedly updating the stored state for as long as the
process is kept running.

## Installation

Once [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `perpetual` to your list of dependencies in `mix.exs`. For now, you
can test the development branch with:

```elixir
def deps do
  [
    {:perpetual, github: "xtagon/perpetual", branch: "edge"}
  ]
end
```
