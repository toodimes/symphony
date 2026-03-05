defmodule SymphonyElixir.Linear.CommentFetcherTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Linear.{Comment, CommentFetcher}

  defp human_comment(id, body, opts \\ []) do
    %Comment{
      id: id,
      body: body,
      user_id: Keyword.get(opts, :user_id, "user-1"),
      user_name: Keyword.get(opts, :user_name, "Alice"),
      created_at: Keyword.get(opts, :created_at, ~U[2026-03-05 10:00:00Z]),
      updated_at: Keyword.get(opts, :updated_at, ~U[2026-03-05 10:00:00Z])
    }
  end

  defp bot_comment(id, body \\ "## Codex Workpad\n\nProgress...\n<!-- symphony-bot -->") do
    %Comment{
      id: id,
      body: body,
      user_id: "user-1",
      user_name: "Alice",
      created_at: ~U[2026-03-05 10:00:00Z],
      updated_at: ~U[2026-03-05 10:00:00Z]
    }
  end

  describe "fetch_new_human_comments/4" do
    test "returns human comments and filters out bot-marked comments" do
      comments = [
        human_comment("c1", "Please fix the edge case"),
        bot_comment("c2"),
        human_comment("c3", "Also check the tests")
      ]

      fetcher = fn _issue_id -> {:ok, comments} end

      {new_comments, seen} =
        CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", %{}, comment_fetcher: fetcher)

      assert length(new_comments) == 2
      assert Enum.map(new_comments, & &1.id) == ["c1", "c3"]
      assert Map.has_key?(seen, "c1")
      assert Map.has_key?(seen, "c2")
      assert Map.has_key?(seen, "c3")
    end

    test "excludes already-seen comments" do
      comments = [
        human_comment("c1", "Old comment"),
        human_comment("c2", "New comment", created_at: ~U[2026-03-05 11:00:00Z], updated_at: ~U[2026-03-05 11:00:00Z])
      ]

      seen = %{"c1" => ~U[2026-03-05 10:00:00Z]}
      fetcher = fn _issue_id -> {:ok, comments} end

      {new_comments, _updated_seen} =
        CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", seen, comment_fetcher: fetcher)

      assert length(new_comments) == 1
      assert hd(new_comments).id == "c2"
    end

    test "detects edited comments by updated_at change" do
      comments = [
        human_comment("c1", "Updated text", updated_at: ~U[2026-03-05 12:00:00Z])
      ]

      seen = %{"c1" => ~U[2026-03-05 10:00:00Z]}
      fetcher = fn _issue_id -> {:ok, comments} end

      {new_comments, updated_seen} =
        CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", seen, comment_fetcher: fetcher)

      assert length(new_comments) == 1
      assert hd(new_comments).body == "Updated text"
      assert updated_seen["c1"] == ~U[2026-03-05 12:00:00Z]
    end

    test "returns empty list and unchanged seen on API error" do
      fetcher = fn _issue_id -> {:error, :network_error} end
      seen = %{"c1" => ~U[2026-03-05 10:00:00Z]}

      {new_comments, returned_seen} =
        capture_log(fn ->
          CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", seen, comment_fetcher: fetcher)
        end)
        |> then(fn _log ->
          CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", seen, comment_fetcher: fetcher)
        end)

      assert new_comments == []
      assert returned_seen == seen
    end

    test "returns empty when all comments are bot-authored" do
      comments = [bot_comment("c1"), bot_comment("c2")]
      fetcher = fn _issue_id -> {:ok, comments} end

      {new_comments, _seen} =
        CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", %{}, comment_fetcher: fetcher)

      assert new_comments == []
    end

    test "returns empty when no comments exist" do
      fetcher = fn _issue_id -> {:ok, []} end

      {new_comments, seen} =
        CommentFetcher.fetch_new_human_comments("issue-1", "SYM-1", %{}, comment_fetcher: fetcher)

      assert new_comments == []
      assert seen == %{}
    end
  end

  describe "format_comments_for_prompt/2" do
    test "returns nil for empty comments" do
      assert CommentFetcher.format_comments_for_prompt([], "Title:") == nil
    end

    test "formats single comment with author and timestamp" do
      comments = [human_comment("c1", "Fix the bug")]

      result = CommentFetcher.format_comments_for_prompt(comments, "New comments:")
      assert result =~ "New comments:"
      assert result =~ "@Alice"
      assert result =~ "Fix the bug"
      assert result =~ "2026-03-05"
    end

    test "formats multiple comments separated by dividers" do
      comments = [
        human_comment("c1", "First comment"),
        human_comment("c2", "Second comment", user_name: "Bob")
      ]

      result = CommentFetcher.format_comments_for_prompt(comments, "Comments:")
      assert result =~ "@Alice"
      assert result =~ "@Bob"
      assert result =~ "First comment"
      assert result =~ "Second comment"
      assert result =~ "---"
    end

    test "truncates long comment bodies" do
      long_body = String.duplicate("a", 5_000)
      comments = [human_comment("c1", long_body)]

      result = CommentFetcher.format_comments_for_prompt(comments, "Comments:")
      assert String.length(result) < 5_000
      assert result =~ "..."
    end

    test "handles nil user_name gracefully" do
      comments = [human_comment("c1", "Some text", user_name: nil)]

      result = CommentFetcher.format_comments_for_prompt(comments, "Comments:")
      assert result =~ "@Unknown"
    end

    test "handles nil created_at gracefully" do
      comments = [human_comment("c1", "Some text", created_at: nil)]

      result = CommentFetcher.format_comments_for_prompt(comments, "Comments:")
      assert result =~ "@Alice"
      assert result =~ "Some text"
    end
  end
end
