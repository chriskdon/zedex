defmodule Zedex.ReplacerTest do
  use ExUnit.Case

  alias Zedex.Replacer
  alias Zedex.Test.{TestModule1, TestModule2}

  doctest Zedex

  setup do
    :ok = Zedex.reset()
  end

  describe "replace/1" do
    test "replaces a function" do
      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)

      :ok =
        Replacer.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
    end

    test "replaces a core erlang function" do
      :ok =
        Replacer.replace([
          {{:rand, :uniform, 1}, {__MODULE__, :constant_uniform, 1}}
        ])

      assert 1 == :rand.uniform(1000)

      :ok = Replacer.reset(:rand)
    end
  end

  describe "reset/0" do
    test "resets all modules back to their original state" do
      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)

      :ok =
        Replacer.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      :ok =
        Replacer.replace([
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)

      :ok = Replacer.reset()

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)
    end
  end

  describe "reset/1" do
    test "resets a list of modules back to their original state" do
      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)

      :ok =
        Replacer.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      :ok =
        Replacer.replace([
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)

      :ok = Replacer.reset([TestModule1, TestModule2])

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)
    end

    test "resets a module back to its original state" do
      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)

      :ok =
        Replacer.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)

      :ok = Replacer.reset(TestModule1)

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
    end
  end

  describe "original_function_mfa/3" do
    test "returns original function MFA when replaced" do
      :ok =
        Replacer.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      {m, f, _arity} = mfa = Replacer.original_function_mfa(TestModule1, :test_func_1, 1)

      assert {Zedex.Test.TestModule1, :__zedex_replacer_original__test_func_1, 1} == mfa
      assert "[#{TestModule1}] Test Func 1 - 123" == apply(m, f, [123])
    end

    test "returns function MFA when not-replaced" do
      {m, f, _arity} = mfa = Replacer.original_function_mfa(TestModule1, :test_func_1, 1)

      assert {Zedex.Test.TestModule1, :test_func_1, 1} == mfa
      assert "[#{TestModule1}] Test Func 1 - 123" == apply(m, f, [123])
    end
  end

  # Used as a replacement function
  def constant_uniform(_n), do: 1
end
