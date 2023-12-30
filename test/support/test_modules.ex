defmodule Zedex.Test.TestModule1 do
  @moduledoc false

  def test_func_1(a) do
    "[#{__MODULE__}] Test Func 1 - #{a}"
  end

  def test_func_2(a) do
    "[#{__MODULE__}] Test Func 2 - #{a}"
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
