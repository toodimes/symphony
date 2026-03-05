defmodule SymphonyElixir.ClaudeStreamParserTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.StreamParser

  test "parses result events and normalizes usage keys" do
    line =
      Jason.encode!(%{
        "type" => "result",
        "input_tokens" => 12,
        "output_tokens" => 8,
        "cost_usd" => 0.12
      })

    assert {:ok, %{event: :turn_completed, usage: usage} = parsed} = StreamParser.parse_line(line)
    assert usage["input_tokens"] == 12
    assert usage["output_tokens"] == 8
    assert usage["total_tokens"] == 20
    assert usage["inputTokens"] == 12
    assert usage["outputTokens"] == 8
    assert usage["totalTokens"] == 20
    assert parsed.payload["type"] == "result"
  end

  test "parses assistant events as notifications" do
    line = Jason.encode!(%{"type" => "assistant", "message" => "hello"})

    assert {:ok, %{event: :notification, payload: payload}} = StreamParser.parse_line(line)
    assert payload["type"] == "assistant"
  end

  test "parses error events as turn failures" do
    line = Jason.encode!(%{"type" => "error", "message" => "boom"})

    assert {:ok, %{event: :turn_failed, payload: payload}} = StreamParser.parse_line(line)
    assert payload["message"] == "boom"
  end

  test "parses unknown event types as notifications" do
    line = Jason.encode!(%{"type" => "tool_use", "name" => "list"})

    assert {:ok, %{event: :notification, payload: payload}} = StreamParser.parse_line(line)
    assert payload["type"] == "tool_use"
  end

  test "returns invalid_json for malformed lines" do
    assert {:error, :invalid_json} = StreamParser.parse_line("not-json")
  end
end
