defmodule SymphonyElixir.Linear.CommentFetcher do
  @moduledoc """
  Fetches and filters Linear issue comments for agent turn context.
  """

  require Logger
  alias SymphonyElixir.Linear.Comment

  @bot_marker "<!-- symphony-bot -->"
  @max_comment_body_chars 4_000
  @max_total_chars 16_000

  @type seen_comments :: %{String.t() => DateTime.t() | nil}

  @spec fetch_new_human_comments(String.t(), String.t() | nil, seen_comments(), keyword()) ::
          {[Comment.t()], seen_comments()}
  def fetch_new_human_comments(issue_id, issue_identifier, seen_comments, opts \\ []) do
    comment_fetcher = Keyword.get(opts, :comment_fetcher, &SymphonyElixir.Tracker.fetch_issue_comments/1)

    case comment_fetcher.(issue_id) do
      {:ok, comments} ->
        new_human_comments =
          comments
          |> Enum.reject(&bot_comment?/1)
          |> Enum.filter(&new_or_edited?(&1, seen_comments))
          |> Enum.sort_by(& &1.created_at, {:asc, DateTime})

        updated_seen =
          Enum.reduce(comments, seen_comments, fn comment, acc ->
            Map.put(acc, comment.id, comment.updated_at)
          end)

        {new_human_comments, updated_seen}

      {:error, reason} ->
        Logger.warning("Failed to fetch comments for issue_id=#{issue_id} issue_identifier=#{issue_identifier}: #{inspect(reason)}")

        {[], seen_comments}
    end
  end

  @spec format_comments_for_prompt([Comment.t()], String.t()) :: String.t() | nil
  def format_comments_for_prompt([], _title), do: nil

  def format_comments_for_prompt(comments, title) do
    {formatted_comments, _remaining} =
      Enum.reduce_while(comments, {[], @max_total_chars}, fn comment, {acc, remaining} ->
        body = truncate_body(comment.body || "")
        body_len = String.length(body)

        if remaining <= 0 do
          {:halt, {acc, 0}}
        else
          used_body =
            if body_len > remaining do
              String.slice(body, 0, remaining) <> "..."
            else
              body
            end

          author = comment.user_name || "Unknown"

          timestamp =
            if comment.created_at, do: " (#{DateTime.to_iso8601(comment.created_at)})", else: ""

          entry = "**@#{author}**#{timestamp}:\n#{used_body}"
          {:cont, {[entry | acc], remaining - String.length(used_body)}}
        end
      end)

    case formatted_comments do
      [] ->
        nil

      entries ->
        body = entries |> Enum.reverse() |> Enum.join("\n\n---\n\n")
        "#{title}\n\n#{body}"
    end
  end

  defp bot_comment?(%Comment{body: body}) when is_binary(body) do
    String.contains?(body, @bot_marker)
  end

  defp bot_comment?(_), do: false

  defp new_or_edited?(%Comment{id: id, updated_at: updated_at}, seen_comments) do
    case Map.get(seen_comments, id) do
      nil -> true
      seen_updated_at -> updated_at != nil and seen_updated_at != nil and DateTime.compare(updated_at, seen_updated_at) == :gt
    end
  end

  defp truncate_body(body) do
    if String.length(body) > @max_comment_body_chars do
      String.slice(body, 0, @max_comment_body_chars) <> "..."
    else
      body
    end
  end
end
