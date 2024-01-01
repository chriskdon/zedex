defmodule ZedexTest do
  use ExUnit.Case

  alias Zedex.Test.{TestModule1, TestModule2, TestModule3}

  doctest Zedex

  setup do
    Zedex.reset()

    # Ensure reset worked correctly. Otherwise none of the tests may be valid.
    assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
    assert "[#{TestModule1}] Test Func 2 - 456" == TestModule1.test_func_2(456)
    assert "[#{TestModule1}] Test Func 3 - 300" == TestModule1.test_func_3(200, 100)
    assert "[#{TestModule1}] Test Func 4 - 400" == TestModule1.test_func_4(300, 100)

    assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)

    :ok
  end

  describe "replace_with/2" do
    test "replaces a function with an anonymous function" do
      :ok =
        Zedex.replace_with({TestModule1, :test_func_1, 1}, fn a ->
          "Hello World: #{a}"
        end)

      assert "Hello World: 123" == TestModule1.test_func_1(123)
    end

    test "can replace a function multiple times" do
      :ok =
        Zedex.replace_with({TestModule1, :test_func_1, 1}, fn a ->
          "Hello World: #{a}"
        end)

      assert "Hello World: 123" == TestModule1.test_func_1(123)

      :ok =
        Zedex.replace_with({TestModule1, :test_func_1, 1}, fn a ->
          "Hello World: #{a + 100}"
        end)

      assert "Hello World: 223" == TestModule1.test_func_1(123)
    end
  end

  describe "replace/1" do
    test "replaces a function" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
    end

    test "replaces a core erlang function" do
      :ok =
        Zedex.replace([
          {{:rand, :uniform, 1}, fn _ -> 1 end}
        ])

      assert 1 == :rand.uniform(1000)

      assert [:rand] = Zedex.reset(:rand)
    end

    test "replaces multiple modules" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}},
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)
    end

    test "can replace with anonymous functions" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1},
           fn a ->
             "Hello World: #{a}"
           end}
        ])

      assert "Hello World: 123" == TestModule1.test_func_1(123)
    end

    test "can mix mfa and anonymous callbacks" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}},
          {{TestModule2, :test_func_1, 1},
           fn a ->
             "Hello World: #{a}"
           end}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "Hello World: 456" == TestModule2.test_func_1(456)
    end
  end

  describe "reset/0" do
    test "resets all modules back to their original state" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}},
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)

      assert [TestModule1, TestModule2] == Zedex.reset() |> Enum.sort()

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)
    end
  end

  describe "reset/1" do
    test "resets a list of modules back to their original state" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}},
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)

      reset_modules = [TestModule1, TestModule2]

      assert reset_modules == Zedex.reset(reset_modules)

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule2}] Test Func 1 - 456" == TestModule2.test_func_1(456)
    end

    test "resets a partial list of modules back to their original state" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}},
          {{TestModule2, :test_func_1, 1}, {TestModule1, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)

      reset_modules = [TestModule1]

      assert [TestModule1] == Zedex.reset(reset_modules)

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
      assert "[#{TestModule1}] Test Func 2 - 456" == TestModule2.test_func_1(456)
    end

    test "resets a module atom back to its original state" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)

      assert [TestModule1] == Zedex.reset(TestModule1)

      assert "[#{TestModule1}] Test Func 1 - 123" == TestModule1.test_func_1(123)
    end
  end

  describe "replace_calls/1" do
    test "replaces a call with an MFA" do
      :ok =
        Zedex.replace_calls(
          {TestModule1, :test_func_3, 2},
          {TestModule3, :add, 2},
          {TestModule3, :sub, 2}
        )

      assert "[#{TestModule1}] Test Func 3 - 100" == TestModule1.test_func_3(200, 100)
      assert "[#{TestModule1}] Test Func 4 - 300" == TestModule1.test_func_4(200, 100)
    end

    test "replaces a call with an anonymous function" do
      :ok =
        Zedex.replace_calls(
          {TestModule1, :test_func_3, 2},
          {TestModule3, :add, 2},
          fn a, b -> a * b end
        )

      assert "[#{TestModule1}] Test Func 3 - 100" == TestModule1.test_func_3(4, 25)
      assert "[#{TestModule1}] Test Func 4 - 29" == TestModule1.test_func_4(4, 25)
    end

    test "can replace spawn and send" do
      test_pid = self()

      fake_pid = :c.pid(0, 999_999, 999_999)

      :ok =
        Zedex.replace_calls(
          {TestModule1, :spawn_and_send, 2},
          {:erlang, :spawn, 1},
          fn f ->
            send(test_pid, {:spawn, f})
            fake_pid
          end
        )

      :ok =
        Zedex.replace_calls(
          {TestModule1, :spawn_and_send, 2},
          {:erlang, :send, 2},
          fn pid, msg ->
            send(pid, {:send, pid, msg})
          end
        )

      assert fake_pid == TestModule1.spawn_and_send(test_pid, "Hello World")

      assert_received {:spawn, func}

      # Call the "spawned" function since we are no longer actually spawning it.
      func.()

      assert_received {:send, ^test_pid, {:message, "Hello World"}}
    end

    @tag :skip
    test "replaces an MFA in an entire module" do
      assert false
    end

    @tag :skip
    test "replaces a call inside nested lambda" do
      assert false
    end
  end

  describe "apply_r/3" do
    test "can call original function" do
      :ok =
        Zedex.replace([
          {{TestModule1, :test_func_1, 1}, {TestModule2, :test_func_2, 1}}
        ])

      assert "[#{TestModule2}] Test Func 2 - 123" == TestModule1.test_func_1(123)

      assert "[#{TestModule1}] Test Func 1 - 123" ==
               Zedex.apply_r(TestModule1, :test_func_1, [123])
    end

    test "can call non-replaced function" do
      assert 3 == Zedex.apply_r(Enum, :count, [[1, 2, 3]])
    end
  end
end
