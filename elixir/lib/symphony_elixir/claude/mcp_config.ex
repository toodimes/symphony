defmodule SymphonyElixir.Claude.McpConfig do
  @moduledoc """
  Writes a temporary Claude MCP config for Symphony dynamic tools.
  """

  alias SymphonyElixir.Config

  @spec write_temp(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def write_temp(workflow_path) when is_binary(workflow_path) do
    config_path =
      Path.join(
        System.tmp_dir!(),
        "symphony-claude-mcp-#{System.unique_integer([:positive])}.json"
      )

    payload = %{
      "mcpServers" => %{
        "symphony-tools" => %{
          "command" => mcp_command(),
          "args" => ["mcp-server", "--workflow", Path.expand(workflow_path)],
          "env" => mcp_env()
        }
      }
    }

    with :ok <- File.write(config_path, Jason.encode!(payload)),
         :ok <- File.chmod(config_path, 0o600) do
      {:ok, config_path}
    else
      {:error, reason} ->
        File.rm(config_path)
        {:error, {:mcp_config_write_failed, reason}}
    end
  end

  @spec cleanup(Path.t() | nil) :: :ok
  def cleanup(path) when is_binary(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} -> :ok
    end
  end

  def cleanup(_path), do: :ok

  defp mcp_command do
    case System.get_env("SYMPHONY_MCP_COMMAND") do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        System.find_executable("symphony") || "symphony"
    end
  end

  defp mcp_env do
    case Config.linear_api_token() do
      token when is_binary(token) and token != "" ->
        %{"LINEAR_API_KEY" => token}

      _ ->
        %{}
    end
  end
end
