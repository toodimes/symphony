defmodule SymphonyElixir.ApplicationTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  describe "startup validation" do
    test "fails when LINEAR_API_KEY is missing" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.delete_env("LINEAR_API_KEY")
        System.put_env("OPENAI_API_KEY", "test_key")

        assert capture_io(:stderr, fn ->
                 result = SymphonyElixir.Application.start(:normal, [])
                 assert {:error, "LINEAR_API_KEY environment variable is not set"} = result
               end) =~ "Startup failed: LINEAR_API_KEY environment variable is not set"
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "fails when OPENAI_API_KEY is missing" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.put_env("LINEAR_API_KEY", "test_key")
        System.delete_env("OPENAI_API_KEY")

        assert capture_io(:stderr, fn ->
                 result = SymphonyElixir.Application.start(:normal, [])
                 assert {:error, "OPENAI_API_KEY environment variable is not set"} = result
               end) =~ "Startup failed: OPENAI_API_KEY environment variable is not set"
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "fails when both environment variables are missing" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.delete_env("LINEAR_API_KEY")
        System.delete_env("OPENAI_API_KEY")

        assert capture_io(:stderr, fn ->
                 result = SymphonyElixir.Application.start(:normal, [])
                 assert {:error, "LINEAR_API_KEY environment variable is not set"} = result
               end) =~ "Startup failed: LINEAR_API_KEY environment variable is not set"
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "fails when environment variables are empty strings" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.put_env("LINEAR_API_KEY", "")
        System.put_env("OPENAI_API_KEY", "test_key")

        assert capture_io(:stderr, fn ->
                 result = SymphonyElixir.Application.start(:normal, [])
                 assert {:error, "LINEAR_API_KEY environment variable is empty"} = result
               end) =~ "Startup failed: LINEAR_API_KEY environment variable is empty"
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end
  end
end
