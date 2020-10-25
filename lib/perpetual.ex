defmodule Perpetual do
  @moduledoc """
  Perpetual is a simple abstraction around repeatedly iterating state.

  It is similar to Elixir's `Agent` module in that it can share or store state
  that must be accessed from different processes or by the same process at
  different points in time, and in additiion to that, `Perpetual` lets you
  define a function for repeatedly updating the stored state for as long as the
  process is kept running.

  The `Perpetual` module provides a basic server implementation that defines an
  update function to be repeatedly applied, and allows current state to be
  retrieved and updated manually via a simple API.

  ## Examples

  For example, the following server implements an infinite counter:

    defmodule Counter do
      use Perpetual

      def start_link(initial_count) do
        args = [init_fun: fn -> initial_count end, next_fun: &(&1 + 1)]
        Perpetual.start_link(args, name: __MODULE__)
      end

      def get_count do
        Perpetual.get(__MODULE__, &(&1))
      end

      def stop do
        Perpetual.stop(__MODULE__)
      end
    end

  Usage would be:

      Counter.start_link(0)
      #=> {:ok, #PID<0.123.0>}

      current_value = Counter.get_count

      later_value = Counter.get_count

      Counter.stop
      #=> :ok

  In the counter example above, the server will keep counting until the process
  is stopped. Each call to `Counter.value()` would retrieve the current count.

  Perpetual provides a segregation between the client and server APIs (similar to
  `GenServer`s). In particular, the functions passed as arguments to the calls to
  `Perpetual` functions are invoked inside the server. This distinction is
  important because you may want to avoid expensive operations inside the
  server for calls to get the current value, as they will effectively block the
  server until the request is fulfilled. However, it is reasonable to do
  expensive work as necessary in the `next_fun` function as that function's
  work is the whole point of iterating perpetually--just be aware of the
  blocking effect is has on other messages. `Perpetual` is designed to be
  long-running and for clients to request the current state only periodically.

  ## How to supervise

  A `Perpetual` server is most commonly started under a supervision tree.
  When we invoke `use Perpetual`, it automatically defines a `child_spec/1`
  function that allows us to start the server directly under a supervisor.
  To start a server under a supervisor with an initial counter of 0,
  one may do:

      children = [
        {Counter, 0}
      ]

      Supervisor.start_link(children, strategy: :one_for_all)

  While one could also simply pass the `Counter` as a child to the supervisor,
  such as:

      children = [
        Counter # Same as {Counter, []}
      ]

      Supervisor.start_link(children, strategy: :one_for_all)

  The definition above wouldn't work for this particular example,
  as it would attempt to start the counter with an initial value
  of an empty list. However, this may be a viable option in your
  own servers. A common approach is to use a keyword list, as that
  would allow setting the initial value and giving a name to the
  counter process, for example:

      def start_link(opts \\ []) do
        {initial_count, opts} = Keyword.pop(opts, :initial_count, 0)
        args = [init_fun: fn -> initial_count end, next_fun: &(&1 + 1)]
        Perpetual.start_link(args, opts)
      end

  and then you can use `Counter`, `{Counter, name: :my_counter}` or
  even `{Counter, initial_count: 0, name: :my_counter}` as a child
  specification.

  `use Perpetual` also accepts a list of options which configures the
  child specification and therefore how it runs under a supervisor.
  The generated `child_spec/1` can be customized with the following options:

    * `:id` - the child specification identifier, defaults to the current module
    * `:restart` - when the child should be restarted, defaults to `:permanent`
    * `:shutdown` - how to shut down the child, either immediately or by giving it time to shut down

  For example:

      use Perpetual, restart: :transient, shutdown: 10_000

  See the "Child specification" section in the `Supervisor` module for more
  detailed information. The `@doc` annotation immediately preceding
  `use Perpetual` will be attached to the generated `child_spec/1` function.

  ## Name registration

  A perpetual server is bound to the same name registration rules as GenServers.
  Read more about it in the `GenServer` documentation.

  ## A word on distributed perpetual servers

  It is important to consider the limitations of distributed perpetual servers.
  Like `Agent`s, `Perpetual` provides two APIs, one that works with anonymous
  functions and another that expects an explicit module, function, and
  arguments.

  In a distributed setup with multiple nodes, the API that accepts anonymous
  functions only works if the caller (client) and the server have the same
  version of the caller module.

  Keep in mind this issue also shows up when performing "rolling upgrades"
  with perpetual servers. By rolling upgrades we mean the following situation:
  you wish to deploy a new version of your software by *shutting down* some of
  your nodes and replacing them with nodes running a new version of the
  software. In this setup, part of your environment will have one version of a
  given module and the other part another version (the newer one) of the same
  module.

  The best solution is to simply use the explicit module, function, and arguments
  APIs when working with distributed perpetual servers.

  ## Hot code swapping

  A perpetual server can have its code hot swapped live by simply passing a
  module, function, and arguments tuple to the update instruction. For example,
  imagine you have a server named `:sample` and you want to convert its inner
  value from a keyword list to a map. It can be done with the following
  instruction:

      {:update, :sample, {:advanced, {Enum, :into, [%{}]}}}

  The server's current value will be added to the given list of arguments
  (`[%{}]`) as the first argument.
  """

  @typedoc "The perpetual server's initial state function"
  @type init_fun_or_mfa :: (() -> term) | {module, atom, [any]}

  @typedoc "The perpetual server's next state function"
  @type next_fun_or_mfa :: ((term) -> term) | {module, atom, [any]}

  @typedoc "Return values of `start*` functions"
  @type on_start :: {:ok, pid} | {:error, {:already_started, pid} | term}

  @typedoc "The perpetual server name"
  @type name :: atom | {:global, term} | {:via, module, term}

  @typedoc "The perpetual server reference"
  @type perpetual :: pid | {atom, node} | name

  @typedoc "The perpetual server value"
  @type state :: term

  @doc """
  Returns a specification to start a perpetual server under a supervisor.

  See the "Child specification" section in the `Supervisor` module for more
  detailed information.
  """
  def child_spec(arg) do
    %{
      id: Perpetual,
      start: {Perpetual, :start_link, [arg]}
    }
  end

  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Returns a specification to start this module under a supervisor.

        See `Supervisor`.
        """
      end

      def child_spec(arg) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]}
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      defoverridable child_spec: 1
    end
  end

  @doc """
  Starts a perpetual server linked to the current process with the given
  function.

  This is often used to start the server as part of a supervision tree.

  Once the server is spawned, the given function `init_fun` is invoked in the
  server process, and should return the initial server state. Note that
  `start_link/2` does not return until the given function has returned.

  Once the server is running, the given function `next_fun` is invoked
  repeatedly in the server process in a loop. This function will be passed the
  current state and should return the next state.

  ## Options

  The `:name` option is used for registration as described in the module
  documentation.

  If the `:timeout` option is present, the server is allowed to spend at most
  the given number of milliseconds on initialization or it will be terminated
  and the start function will return `{:error, :timeout}`.

  If the `:debug` option is present, the corresponding function in the
  [`:sys` module](http://www.erlang.org/doc/man/sys.html) will be invoked.

  If the `:spawn_opt` option is present, its value will be passed as options
  to the underlying process as in `Process.spawn/4`.

  ## Return values

  If the server is successfully created and initialized, the function returns
  `{:ok, pid}`, where `pid` is the PID of the server. If an server with the
  specified name already exists, the function returns
  `{:error, {:already_started, pid}}` with the PID of that process.

  If the given function callback fails, the function returns `{:error, reason}`.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> _value = Perpetual.get(pid, fn state -> state end)

      iex> {:error, {exception, _stacktrace}} = Perpetual.start(init_fun: fn -> raise "oops" end, next_fun: &(&1 + 1))
      iex> exception
      %RuntimeError{message: "oops"}

  """
  @spec start_link([init_fun: init_fun_or_mfa, next_fun: next_fun_or_mfa], GenServer.options()) :: on_start
  def start_link(args, options \\ []) do
    args = Keyword.take(args, [:init_fun, :next_fun])
    GenServer.start_link(Perpetual.Server, args, options)
  end

  @doc """
  Starts a perpetual server process without links (outside of a supervision
  tree).

  See `start_link/2` for more information.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> _value = Perpetual.get(pid, fn state -> state end)

  """
  @spec start([init_fun: init_fun_or_mfa, next_fun: next_fun_or_mfa], GenServer.options()) :: on_start
  def start(args, options \\ []) do
    args = Keyword.take(args, [:init_fun, :next_fun])
    GenServer.start(Perpetual.Server, args, options)
  end

  @doc """
  Gets a perpetual server's value via the given anonymous function.

  The function `fun` is sent to the `perpetual` which invokes the function
  passing the server's state. The result of the function invocation is
  returned from this function.

  `timeout` is an integer greater than zero which specifies how many
  milliseconds are allowed before the server executes the function and returns
  the result value, or the atom `:infinity` to wait indefinitely. If no result
  is received within the specified time, the function call fails and the caller
  exits.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> _value = Perpetual.get(pid, fn state -> state end)

  """
  @spec get(perpetual, (state -> a), timeout) :: a when a: var
  def get(perpetual, fun, timeout \\ 5000) when is_function(fun, 1) do
    GenServer.call(perpetual, {:get, fun}, timeout)
  end

  @doc """
  Gets a perpetual server's value via the given function.

  Same as `get/3` but a module, function, and arguments are expected
  instead of an anonymous function. The state is added as first
  argument to the given list of arguments.
  """
  @spec get(perpetual, module, atom, [term], timeout) :: any
  def get(perpetual, module, fun, args, timeout \\ 5000) do
    GenServer.call(perpetual, {:get, {module, fun, args}}, timeout)
  end

  @doc """
  Gets and updates the perpetual server's state in one operation via the given
  anonymous function.

  The function `fun` is sent to the `perpetual` which invokes the function
  passing the current state. The function must return a tuple with two
  elements, the first being the value to return (that is, the "get" value)
  and the second one being the new state of the perpetual server.

  `timeout` is an integer greater than zero which specifies how many
  milliseconds are allowed before the server executes the function and returns
  the result value, or the atom `:infinity` to wait indefinitely. If no result
  is received within the specified time, the function call fails and the caller
  exits.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> _current_value = Perpetual.get_and_update(pid, fn state -> {state, -1 * state} end)
      iex> _later_value = Perpetual.get(pid, fn state -> state end)

  """
  @spec get_and_update(perpetual, (state -> {a, state}), timeout) :: a when a: var
  def get_and_update(perpetual, fun, timeout \\ 5000) when is_function(fun, 1) do
    GenServer.call(perpetual, {:get_and_update, fun}, timeout)
  end

  @doc """
  Gets and updates the perpetual state in one operation via the given function.

  Same as `get_and_update/3` but a module, function, and arguments are expected
  instead of an anonymous function. The state is added as first
  argument to the given list of arguments.
  """
  @spec get_and_update(perpetual, module, atom, [term], timeout) :: any
  def get_and_update(perpetual, module, fun, args, timeout \\ 5000) do
    GenServer.call(perpetual, {:get_and_update, {module, fun, args}}, timeout)
  end

  @doc """
  Updates the perpetual server's state via the given anonymous function.

  The function `fun` is sent to the `perpetual` which invokes the function
  passing the current state. The return value of `fun` becomes the new
  state of the server.

  This function always returns `:ok`.

  `timeout` is an integer greater than zero which specifies how many
  milliseconds are allowed before the perpetual executes the function and returns
  the result value, or the atom `:infinity` to wait indefinitely. If no result
  is received within the specified time, the function call fails and the caller
  exits.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> Perpetual.update(pid, fn state -> -1 * state end)
      :ok
      iex> _value = Perpetual.get(pid, fn state -> state end)

  """
  @spec update(perpetual, (state -> state), timeout) :: :ok
  def update(perpetual, fun, timeout \\ 5000) when is_function(fun, 1) do
    GenServer.call(perpetual, {:update, fun}, timeout)
  end

  @doc """
  Updates the perpetual server's state via the given function.

  Same as `update/3` but a module, function, and arguments are expected
  instead of an anonymous function. The state is added as first
  argument to the given list of arguments.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> Perpetual.update(pid, Kernel, :*, [-1])
      :ok
      iex> _value = Perpetual.get(pid, fn state -> state end)

  """
  @spec update(perpetual, module, atom, [term], timeout) :: :ok
  def update(perpetual, module, fun, args, timeout \\ 5000) do
    GenServer.call(perpetual, {:update, {module, fun, args}}, timeout)
  end

  @doc """
  Performs a cast (*fire and forget*) operation on the perpetual server's
  state.

  The function `fun` is sent to the `perpetual` which invokes the function
  passing the current state. The return value of `fun` becomes the new
  state of the server.

  Note that `cast` returns `:ok` immediately, regardless of whether `perpetual`
  (or the node it should live on) exists.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> Perpetual.cast(pid, fn state -> -1 * state end)
      :ok
      iex> _value = Perpetual.get(pid, fn state -> state end)

  """
  @spec cast(perpetual, (state -> state)) :: :ok
  def cast(perpetual, fun) when is_function(fun, 1) do
    GenServer.cast(perpetual, {:cast, fun})
  end

  @doc """
  Performs a cast (*fire and forget*) operation on the perpetual server's
  state.

  Same as `cast/2` but a module, function, and arguments are expected
  instead of an anonymous function. The state is added as first
  argument to the given list of arguments.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> Perpetual.cast(pid, Kernel, :*, [-1])
      :ok
      iex> _value = Perpetual.get(pid, fn state -> state end)

  """
  @spec cast(perpetual, module, atom, [term]) :: :ok
  def cast(perpetual, module, fun, args) do
    GenServer.cast(perpetual, {:cast, {module, fun, args}})
  end

  @doc """
  Synchronously stops the perpetual server with the given `reason`.

  It returns `:ok` if the server terminates with the given reason. If the
  server terminates with another reason, the call will exit.

  This function keeps OTP semantics regarding error reporting.
  If the reason is any other than `:normal`, `:shutdown` or
  `{:shutdown, _}`, an error report will be logged.

  ## Examples

      iex> {:ok, pid} = Perpetual.start_link(init_fun: fn -> 0 end, next_fun: &(&1 + 1))
      iex> Perpetual.stop(pid)
      :ok

  """
  @spec stop(perpetual, reason :: term, timeout) :: :ok
  def stop(perpetual, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(perpetual, reason, timeout)
  end
end
