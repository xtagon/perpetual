defmodule Perpetual.Server do
  @moduledoc false

  use GenServer

  @timeout 0

  def init(opts \\ []) do
    init_fun = Keyword.fetch!(opts, :init_fun)
    next_fun = Keyword.fetch!(opts, :next_fun)

    _ = initial_call(init_fun, next_fun)

    init_value = run(init_fun, [])

    state = %{
      next_fun: next_fun,
      value: init_value
    }

    {:ok, state, @timeout}
  end

  def handle_info(:timeout, state) do
    next_value = run(state.next_fun, [state.value])
    next_state = %{state | value: next_value}

    {:noreply, next_state, @timeout}
  end

  def handle_call({:get, fun}, _from, state) do
    {:reply, run(fun, [state.value]), state, @timeout}
  end

  def handle_call({:get_and_update, fun}, _from, state) do
    case run(fun, [state.value]) do
      {reply, next_value} ->
        next_state = %{state | value: next_value}
        {:reply, reply, next_state, @timeout}
      other ->
        {:stop, {:bad_return_value, other}, state}
    end
  end

  def handle_call({:update, fun}, _from, state) do
    next_value = run(fun, [state.value])
    next_state = %{state | value: next_value}

    {:reply, :ok, next_state, @timeout}
  end

  def handle_call({:swarm, :begin_handoff}, _from, state) do
    {:reply, {:resume, state}, state, @timeout}
  end

  def handle_call({:swarm, :end_handoff, incoming_state}, _from, _state) do
    {:noreply, incoming_state, @timeout}
  end

  def handle_cast({:cast, fun}, state) do
    next_value = run(fun, [state.value])
    next_state = %{state | value: next_value}

    {:noreply, next_state, @timeout}
  end

  def code_change(_old, state, fun) do
    next_value = run(fun, [state.value])
    next_state = %{state | value: next_value}

    {:ok, next_state}
  end

  defp initial_call(init_fun, next_fun) do
    _ = Process.put(:"$initial_call", get_initial_call(init_fun))
    _ = Process.put(:"$next_call", get_initial_call(next_fun))
    :ok
  end

  defp get_initial_call(fun) when is_function(fun, 0) do
    {:module, module} = Function.info(fun, :module)
    {:name, name} = Function.info(fun, :name)
    {module, name, 0}
  end

  defp get_initial_call(fun) when is_function(fun, 1) do
    {:module, module} = Function.info(fun, :module)
    {:name, name} = Function.info(fun, :name)
    {module, name, 1}
  end

  defp get_initial_call({mod, fun, args}) do
    {mod, fun, length(args)}
  end

  defp run({m, f, a}, extra), do: apply(m, f, extra ++ a)
  defp run(fun, extra), do: apply(fun, extra)
end
