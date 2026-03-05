defmodule SymphonyElixir.ClaudeMcpConfigTest do
  use SymphonyElixir.TestSupport
  import Bitwise

  alias SymphonyElixir.Claude.McpConfig

  test "writes secure mcp config file for symphony tools server" do
    previous_path = System.get_env("SYMPHONY_MCP_COMMAND")
    fake_command = Path.expand("bin/symphony-fake")

    on_exit(fn ->
      if is_binary(previous_path) do
        System.put_env("SYMPHONY_MCP_COMMAND", previous_path)
      else
        System.delete_env("SYMPHONY_MCP_COMMAND")
      end
    end)

    System.put_env("SYMPHONY_MCP_COMMAND", fake_command)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_api_token: "linear-token"
    )

    assert {:ok, config_path} = McpConfig.write_temp(Workflow.workflow_file_path())
    assert File.exists?(config_path)

    assert {:ok, stat} = File.stat(config_path)
    assert (stat.mode &&& 0o777) == 0o600

    payload = config_path |> File.read!() |> Jason.decode!()

    assert payload["mcpServers"]["symphony-tools"]["command"] == fake_command
    assert payload["mcpServers"]["symphony-tools"]["args"] == ["mcp-server", "--workflow", Workflow.workflow_file_path()]
    assert payload["mcpServers"]["symphony-tools"]["env"]["LINEAR_API_KEY"] == "linear-token"

    assert :ok = McpConfig.cleanup(config_path)
    refute File.exists?(config_path)
  end
end
