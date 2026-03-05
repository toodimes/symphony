defmodule SymphonyElixir.Claude.McpServer do
  @moduledoc """
  Minimal MCP stdio server exposing Symphony dynamic tools.
  """

  alias SymphonyElixir.Codex.DynamicTool

  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    tool_executor =
      Keyword.get(opts, :tool_executor, fn tool, arguments ->
        DynamicTool.execute(tool, arguments)
      end)

    loop_stdio(tool_executor)
  end

  @doc false
  @spec handle_request_for_test(map(), keyword()) :: map()
  def handle_request_for_test(request, opts \\ []) when is_map(request) and is_list(opts) do
    tool_executor =
      Keyword.get(opts, :tool_executor, fn tool, arguments ->
        DynamicTool.execute(tool, arguments)
      end)

    handle_request(request, tool_executor)
  end

  defp loop_stdio(tool_executor) do
    case IO.read(:line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line when is_binary(line) ->
        line
        |> String.trim()
        |> case do
          "" ->
            :ok

          content ->
            response =
              case Jason.decode(content) do
                {:ok, %{} = request} ->
                  handle_request(request, tool_executor)

                {:error, _reason} ->
                  error_response(nil, -32700, "Parse error")
              end

            IO.puts(Jason.encode!(response))
        end

        loop_stdio(tool_executor)
    end
  end

  defp handle_request(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/list"}, _tool_executor) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "tools" => Enum.map(DynamicTool.tool_specs(), &mcp_tool_spec/1)
      }
    }
  end

  defp handle_request(
         %{
           "jsonrpc" => "2.0",
           "id" => id,
           "method" => "tools/call",
           "params" => %{"name" => tool_name} = params
         },
         tool_executor
       )
       when is_binary(tool_name) and is_function(tool_executor, 2) do
    arguments = Map.get(params, "arguments", %{})
    result = tool_executor.(tool_name, arguments)
    is_error = !(is_map(result) and Map.get(result, "success") == true)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "content" => [
          %{
            "type" => "text",
            "text" => Jason.encode!(result, pretty: true)
          }
        ],
        "isError" => is_error
      }
    }
  end

  defp handle_request(%{"jsonrpc" => "2.0", "id" => id, "method" => _method}, _tool_executor) do
    error_response(id, -32601, "Method not found")
  end

  defp handle_request(%{"id" => id}, _tool_executor) do
    error_response(id, -32600, "Invalid Request")
  end

  defp handle_request(_request, _tool_executor) do
    error_response(nil, -32600, "Invalid Request")
  end

  defp mcp_tool_spec(%{
         "name" => name,
         "description" => description,
         "inputSchema" => input_schema
       }) do
    %{
      "name" => name,
      "description" => description,
      "inputSchema" => input_schema
    }
  end

  defp mcp_tool_spec(other), do: other

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end
end
