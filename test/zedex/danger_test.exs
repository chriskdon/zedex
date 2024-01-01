defmodule Zedex.DangerTest do
  use ExUnit.Case

  alias Zedex.Danger, as: ZedexDanger
  alias Zedex.Test.{TestModule1, TestModule2, TestModule3}

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

  describe "replace_calls/1" do
    test "replaces a call with an MFA" do
      :ok =
        ZedexDanger.replace_calls(
          {TestModule1, :test_func_3, 2},
          {TestModule3, :add, 2},
          {TestModule3, :sub, 2}
        )

      assert "[#{TestModule1}] Test Func 3 - 100" == TestModule1.test_func_3(200, 100)
      assert "[#{TestModule1}] Test Func 4 - 300" == TestModule1.test_func_4(200, 100)
    end

    test "replaces a call with an anonymous function" do
      :ok =
        ZedexDanger.replace_calls(
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
        ZedexDanger.replace_calls(
          {TestModule1, :spawn_and_send, 2},
          {:erlang, :spawn, 1},
          fn f ->
            send(test_pid, {:spawn, f})
            fake_pid
          end
        )

      :ok =
        ZedexDanger.replace_calls(
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
end
