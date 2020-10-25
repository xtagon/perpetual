defmodule PerpetualTest do
  use ExUnit.Case, async: true

  doctest Perpetual

  def identity(state) do
    state
  end

  test "can be supervised directly" do
    children = [
      {Perpetual, init_fun: fn -> :ok end, next_fun: &(&1)}
    ]

    assert {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  end

  test "generates child_spec/1" do
    defmodule MyPerpetual do
      use Perpetual
    end

    assert MyPerpetual.child_spec([:hello]) == %{
      id: MyPerpetual,
      start: {MyPerpetual, :start_link, [[:hello]]}
    }

    defmodule CustomPerpetual do
      use Perpetual,
        id: :id,
        restart: :temporary,
        shutdown: :infinity,
        start: {:foo, :bar, []}
    end

    assert CustomPerpetual.child_spec([:hello]) == %{
      id: :id,
      restart: :temporary,
      shutdown: :infinity,
      start: {:foo, :bar, []}
    }
  end

  test "start_link/2 update workflow with unregistered name and anonymous functions" do
    {:ok, pid} = Perpetual.start_link(init_fun: &Map.new/0, next_fun: &(&1))

    {:links, links} = Process.info(self(), :links)
    assert pid in links

    assert :proc_lib.translate_initial_call(pid) == {Map, :new, 0}

    assert Perpetual.update(pid, &Map.put(&1, :hello, :world)) == :ok
    assert Perpetual.get(pid, &Map.get(&1, :hello), 3000) == :world
    assert Perpetual.get_and_update(pid, &Map.pop(&1, :hello), 3000) == :world
    assert Perpetual.get(pid, & &1) == %{}
    assert Perpetual.stop(pid) == :ok
    wait_until_dead(pid)
  end

  test "start_link/2 with spawn_opt" do
    args = [init_fun: fn -> 0 end, next_fun: &(&1)]
    options = [spawn_opt: [priority: :high]]

    {:ok, pid} = Perpetual.start_link(args, options)

    assert Process.info(pid, :priority) == {:priority, :high}
  end

  test "start/2 update workflow with registered name and module functions" do
    args = [init_fun: {Map, :new, []}, next_fun: {PerpetualTest, :identity, []}]

    {:ok, pid} = Perpetual.start(args, name: :perpetual)

    assert Process.info(pid, :registered_name) == {:registered_name, :perpetual}
    assert :proc_lib.translate_initial_call(pid) == {Map, :new, 0}
    assert Perpetual.cast(:perpetual, Map, :put, [:hello, :world]) == :ok
    assert Perpetual.get(:perpetual, Map, :get, [:hello]) == :world
    assert Perpetual.get_and_update(:perpetual, Map, :pop, [:hello]) == :world
    assert Perpetual.get(:perpetual, PerpetualTest, :identity, []) == %{}
    assert Perpetual.stop(:perpetual) == :ok
    assert Process.info(pid, :registered_name) == nil
  end

  test "example counter module" do
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

    {:ok, _pid} = Counter.start_link(0)

    Process.sleep(5)
    count1 = Counter.get_count
    Process.sleep(5)
    count2 = Counter.get_count

    assert count1 > 0
    assert count2 > count1

    assert Counter.stop == :ok
  end

  test "example counter module with supervisor" do
    defmodule SupervisedCounter do
      use Perpetual

      def start_link(opts \\ []) do
        {initial_count, opts} = Keyword.pop(opts, :initial_count, 0)

        opts = Keyword.put_new(opts, :name, __MODULE__)
        args = [init_fun: fn -> initial_count end, next_fun: &(&1 + 1)]

        Perpetual.start_link(args, opts)
      end

      def get_count do
        Perpetual.get(__MODULE__, &(&1))
      end

      def stop do
        Perpetual.stop(__MODULE__)
      end
    end

    children = [
      SupervisedCounter
      # Same as:
      #{SupervisedCounter, initial_count: 0}
    ]

    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_all)

    Process.sleep(5)
    count1 = SupervisedCounter.get_count
    Process.sleep(5)
    count2 = SupervisedCounter.get_count

    assert count1 > 0
    assert count2 > count1

    assert SupervisedCounter.stop == :ok
  end

  test ":sys.change_code/4 with mfa" do
    args = [init_fun: fn -> %{} end, next_fun: {PerpetualTest, :identity, []}]
    {:ok, pid} = Perpetual.start_link(args)
    :ok = :sys.suspend(pid)
    mfa = {Map, :put, [:hello, :world]}
    assert :sys.change_code(pid, __MODULE__, "vsn", mfa) == :ok
    :ok = :sys.resume(pid)
    assert Perpetual.get(pid, &Map.get(&1, :hello)) == :world
    assert Perpetual.stop(pid) == :ok
  end

  test ":sys.change_code/4 with raising mfa" do
    args = [init_fun: fn -> %{} end, next_fun: {PerpetualTest, :identity, []}]
    {:ok, pid} = Perpetual.start_link(args)
    :ok = :sys.suspend(pid)
    mfa = {:erlang, :error, []}
    assert match?({:error, _}, :sys.change_code(pid, __MODULE__, "vsn", mfa))
    :ok = :sys.resume(pid)
    assert Perpetual.get(pid, & &1) == %{}
    assert Perpetual.stop(pid) == :ok
  end

  defp wait_until_dead(pid) do
    if Process.alive?(pid) do
      wait_until_dead(pid)
    end
  end
end
