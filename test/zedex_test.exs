defmodule ZedexTest do
  use ExUnit.Case

  alias Zedex.Test.{TestModule1, TestModule2}

  doctest Zedex

  setup do
    :ok = Zedex.reset()
  end

  describe "replace/1" do
    # These are smoke tests, the complete tests are in `Zedex.ReplacerTest`

    test "replaces a function" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
    end
  end

  describe "reset/0" do
    # These are smoke tests, the complete tests are in `Zedex.ReplacerTest`

    test "resets all modules back to their original state" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)

      :ok = Zedex.reset()

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
    end
  end

  describe "reset/1" do
    # These are smoke tests, the complete tests are in `Zedex.ReplacerTest`

    test "resets a list of modules back to their original state" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      :ok =
        Zedex.replace([
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      :ok = Zedex.reset([TestModule1, TestModule2])

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)
    end
  end

  describe "apply_original/3" do
    test "can call original function with apply_original" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)

      assert "[#{TestModule1}] Test Func 1 - 123" ==
               Zedex.apply_original(TestModule1, :test_func_1, [123])
    end

    test "can call non-replaced function" do
      assert 3 == Zedex.apply_original(Enum, :count, [[1, 2, 3]])
    end
  end
end
