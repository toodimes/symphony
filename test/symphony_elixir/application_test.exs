defmodule SymphonyElixir.ApplicationTest do
  use ExUnit.Case, async: true

  # Access private functions for testing
  defp check_linear_api_key do
    case System.get_env("LINEAR_API_KEY") do
      nil -> {:error, "LINEAR_API_KEY environment variable is not set"}
      "" -> {:error, "LINEAR_API_KEY environment variable is empty"}
      _ -> :ok
    end
  end

  defp check_openai_api_key do
    case System.get_env("OPENAI_API_KEY") do
      nil -> {:error, "OPENAI_API_KEY environment variable is not set"}
      "" -> {:error, "OPENAI_API_KEY environment variable is empty"}
      _ -> :ok
    end
  end

  defp validate_required_env_vars_non_test do
    with :ok <- check_linear_api_key() do
      check_openai_api_key()
    end
  end

  describe "startup validation functions" do
    test "check_linear_api_key fails when LINEAR_API_KEY is missing" do
      old_linear = System.get_env("LINEAR_API_KEY")

      try do
        System.delete_env("LINEAR_API_KEY")
        assert {:error, "LINEAR_API_KEY environment variable is not set"} = check_linear_api_key()
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
      end
    end

    test "check_linear_api_key fails when LINEAR_API_KEY is empty" do
      old_linear = System.get_env("LINEAR_API_KEY")

      try do
        System.put_env("LINEAR_API_KEY", "")
        assert {:error, "LINEAR_API_KEY environment variable is empty"} = check_linear_api_key()
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
      end
    end

    test "check_openai_api_key fails when OPENAI_API_KEY is missing" do
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.delete_env("OPENAI_API_KEY")
        assert {:error, "OPENAI_API_KEY environment variable is not set"} = check_openai_api_key()
      after
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "check_openai_api_key fails when OPENAI_API_KEY is empty" do
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.put_env("OPENAI_API_KEY", "")
        assert {:error, "OPENAI_API_KEY environment variable is empty"} = check_openai_api_key()
      after
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "validation passes when both environment variables are set" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.put_env("LINEAR_API_KEY", "test_key")
        System.put_env("OPENAI_API_KEY", "test_key")
        assert :ok = validate_required_env_vars_non_test()
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "validation fails when LINEAR_API_KEY is missing" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.delete_env("LINEAR_API_KEY")
        System.put_env("OPENAI_API_KEY", "test_key")
        assert {:error, "LINEAR_API_KEY environment variable is not set"} = validate_required_env_vars_non_test()
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end

    test "validation fails when OPENAI_API_KEY is missing" do
      old_linear = System.get_env("LINEAR_API_KEY")
      old_openai = System.get_env("OPENAI_API_KEY")

      try do
        System.put_env("LINEAR_API_KEY", "test_key")
        System.delete_env("OPENAI_API_KEY")
        assert {:error, "OPENAI_API_KEY environment variable is not set"} = validate_required_env_vars_non_test()
      after
        if old_linear, do: System.put_env("LINEAR_API_KEY", old_linear)
        if old_openai, do: System.put_env("OPENAI_API_KEY", old_openai)
      end
    end
  end
end
