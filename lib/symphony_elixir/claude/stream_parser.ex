defmodule SymphonyElixir.Claude.StreamParser do
  @moduledoc """
  Parses Claude CLI `stream-json` lines into normalized Symphony event payloads.
  """

  @type parsed_event :: %{
          event: :turn_completed | :turn_failed | :notification,
          payload: map(),
          usage: map() | nil
        }

  @spec parse_line(String.t()) :: {:ok, parsed_event()} | {:error, :invalid_json}
  def parse_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "result"} = payload} ->
        {:ok,
         %{
           event: :turn_completed,
           payload: payload,
           usage: normalize_usage(payload)
         }}

      {:ok, %{"type" => "error"} = payload} ->
        {:ok, %{event: :turn_failed, payload: payload, usage: nil}}

      {:ok, %{} = payload} ->
        {:ok, %{event: :notification, payload: payload, usage: nil}}

      {:error, _reason} ->
        {:error, :invalid_json}
    end
  end

  defp normalize_usage(payload) do
    input_tokens = non_negative_integer(Map.get(payload, "input_tokens"))
    output_tokens = non_negative_integer(Map.get(payload, "output_tokens"))
    total_tokens = input_tokens + output_tokens

    %{
      "input_tokens" => input_tokens,
      "output_tokens" => output_tokens,
      "total_tokens" => total_tokens,
      "inputTokens" => input_tokens,
      "outputTokens" => output_tokens,
      "totalTokens" => total_tokens
    }
  end

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: 0
end
