defmodule Zedex.Test.TestModule1 do
  @moduledoc false

  alias Zedex.Test.TestModule3

  def test_func_1(a) do
    "[#{__MODULE__}] Test Func 1 - #{a}"
  end

  def test_func_2(a) do
    "[#{__MODULE__}] Test Func 2 - #{a}"
  end

  def test_func_3(a, b) do
    "[#{__MODULE__}] Test Func 3 - #{TestModule3.add(a, b)}"
  end

  def test_func_4(a, b) do
    "[#{__MODULE__}] Test Func 4 - #{TestModule3.add(a, b)}"
  end

  def spawn_and_send(receiver, message) do
    pid =
      spawn(fn ->
        send(receiver, {:message, message})
      end)

    pid
  end
end

defmodule Zedex.Test.TestModule2 do
  @moduledoc false

  def test_func_1(a) do
    "[#{__MODULE__}] Test Func 1 - #{a}"
  end

  def test_func_2(a) do
    "[#{__MODULE__}] Test Func 2 - #{a}"
  end
end

defmodule Zedex.Test.TestModule3 do
  @moduledoc false

  def add(a, b), do: a + b
  def sub(a, b), do: a - b
end
