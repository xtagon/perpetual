# Perpetual

Perpetual is a simple abstraction around repeatedly iterating state in Elixir.

It is similar to Elixir's `Agent` module in that it can share or store state
that must be accessed from different processes or by the same process at
different points in time, and in additiion to that, `Perpetual` lets you
define a function for repeatedly updating the stored state for as long as the
process is kept running.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `perpetual` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:perpetual, "~> 0.0.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/perpetual](https://hexdocs.pm/perpetual).
