defmodule SymphonyElixir.ClaudeCliRunnerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Claude.CliRunner

  test "claude runner starts a resumable session and streams turn updates" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-claude-runner-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-claude")
      claude_binary = Path.join(test_root, "fake-claude")
      trace_file = Path.join(test_root, "claude.trace")

      File.mkdir_p!(workspace)

      File.write!(claude_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CLAUDE_TRACE:-/tmp/claude.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"

      printf '%s\\n' '{"type":"assistant","message":{"content":"working"}}'
      printf '%s\\n' '{"type":"result","input_tokens":7,"output_tokens":5,"cost_usd":0.12}'
      """)

      File.chmod!(claude_binary, 0o755)
      System.put_env("SYMP_TEST_CLAUDE_TRACE", trace_file)
      on_exit(fn -> System.delete_env("SYMP_TEST_CLAUDE_TRACE") end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend: "claude",
        claude_command: claude_binary,
        claude_permission_mode: "bypassPermissions"
      )

      issue = %Issue{
        id: "issue-claude",
        identifier: "MT-claude",
        title: "Claude run",
        description: "stream json test",
        state: "In Progress",
        url: "https://example.org/issues/MT-claude",
        labels: []
      }

      test_pid = self()
      on_message = fn message -> send(test_pid, {:update, message}) end

      assert {:ok, session} = CliRunner.start_session(workspace)
      mcp_config_path = session.mcp_config_path
      assert File.exists?(mcp_config_path)
      assert {:ok, first_turn} = CliRunner.run_turn(session, "First prompt", issue, on_message: on_message)
      assert String.ends_with?(first_turn.session_id, "-turn-1")

      assert_received {:update, %{event: :session_started, session_id: first_session_id}}
      assert first_session_id == first_turn.session_id

      assert_received {:update, %{event: :turn_completed, usage: usage}}
      assert usage["input_tokens"] == 7
      assert usage["output_tokens"] == 5
      assert usage["total_tokens"] == 12

      assert {:ok, second_turn} = CliRunner.run_turn(session, "Second prompt", issue, on_message: on_message)
      assert String.ends_with?(second_turn.session_id, "-turn-2")
      assert :ok = CliRunner.stop_session(session)
      refute File.exists?(mcp_config_path)

      trace_lines = trace_file |> File.read!() |> String.split("\n", trim: true)

      first_argv = Enum.at(Enum.filter(trace_lines, &String.starts_with?(&1, "ARGV:")), 0)
      second_argv = Enum.at(Enum.filter(trace_lines, &String.starts_with?(&1, "ARGV:")), 1)

      assert first_argv =~ "--print"
      assert first_argv =~ "--output-format stream-json"
      assert first_argv =~ "--permission-mode bypassPermissions"
      assert first_argv =~ "--session-id"
      assert second_argv =~ "--resume"
      refute second_argv =~ "--session-id"
    after
      File.rm_rf(test_root)
    end
  end

  test "port_exit error includes stderr output from the CLI" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-claude-exit-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-fail")
      claude_binary = Path.join(test_root, "fake-claude-fail")

      File.mkdir_p!(workspace)

      File.write!(claude_binary, """
      #!/bin/sh
      echo "Error: Invalid model specified"
      echo "Please check your configuration"
      exit 1
      """)

      File.chmod!(claude_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend: "claude",
        claude_command: claude_binary,
        claude_permission_mode: "bypassPermissions"
      )

      issue = %Issue{
        id: "issue-fail",
        identifier: "MT-fail",
        title: "Failing run",
        description: "error capture test",
        state: "In Progress",
        url: "https://example.org/issues/MT-fail",
        labels: []
      }

      assert {:ok, session} = CliRunner.start_session(workspace)

      assert {:error, {:port_exit, 1, context}} =
               CliRunner.run_turn(session, "prompt", issue)

      assert context =~ "Invalid model specified"
      assert context =~ "Please check your configuration"

      :ok = CliRunner.stop_session(session)
    after
      File.rm_rf(test_root)
    end
  end
end
