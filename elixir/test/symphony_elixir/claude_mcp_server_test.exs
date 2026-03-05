defmodule SymphonyElixir.ClaudeMcpServerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.McpServer

  test "tools/list returns symphony dynamic tools in MCP format" do
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

    assert %{"jsonrpc" => "2.0", "id" => 1, "result" => %{"tools" => tools}} =
             McpServer.handle_request_for_test(request)

    assert Enum.any?(tools, fn tool ->
             tool["name"] == "linear_graphql" and is_map(tool["inputSchema"])
           end)
  end

  test "tools/call delegates to provided tool executor" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "linear_graphql",
        "arguments" => %{"query" => "{ viewer { id } }"}
      }
    }

    tool_executor = fn tool, args ->
      %{"success" => true, "tool" => tool, "args" => args}
    end

    assert %{
             "jsonrpc" => "2.0",
             "id" => 2,
             "result" => %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => text_payload
                 }
               ],
               "isError" => false
             }
           } = McpServer.handle_request_for_test(request, tool_executor: tool_executor)

    decoded = Jason.decode!(text_payload)
    assert decoded["tool"] == "linear_graphql"
    assert decoded["args"]["query"] == "{ viewer { id } }"
  end
end
