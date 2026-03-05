defmodule SymphonyElixir.Claude.CliRunner do
  @moduledoc """
  Runs Claude Code CLI turns with `stream-json` output and session resumption.
  """

  @behaviour SymphonyElixir.Backend

  require Logger
  import Bitwise

  alias SymphonyElixir.{Claude.McpConfig, Claude.StreamParser, Config, Workflow}

  @port_line_bytes 1_048_576
  @max_stream_log_bytes 1_000

  @type session :: %{
          conversation_id: String.t(),
          workspace: Path.t(),
          turn_counter: pid(),
          mcp_config_path: Path.t(),
          cleanup_mcp_config?: boolean()
        }

  @spec start_session(Path.t()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace) do
    with :ok <- validate_workspace_cwd(workspace),
         {:ok, counter} <- Agent.start_link(fn -> 0 end) do
      case mcp_config_for_session() do
        {:ok, mcp_config_path, cleanup_mcp_config?} ->
          {:ok,
           %{
             conversation_id: uuid_v4(),
             workspace: Path.expand(workspace),
             turn_counter: counter,
             mcp_config_path: mcp_config_path,
             cleanup_mcp_config?: cleanup_mcp_config?
           }}

        {:error, reason} ->
          Agent.stop(counter)
          {:error, reason}
      end
    end
  end

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(
        %{
          conversation_id: conversation_id,
          workspace: workspace,
          turn_counter: turn_counter,
          mcp_config_path: mcp_config_path
        },
        prompt,
        issue,
        opts \\ []
      )
      when is_binary(prompt) and is_binary(conversation_id) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)

    with {:ok, permission_mode} <- resolve_permission_mode(),
         {:ok, turn_number} <- next_turn_number(turn_counter),
         {:ok, prompt_file} <- write_prompt_file(prompt) do
      try do
        with {:ok, port, metadata} <-
               start_port(
                 workspace,
                 conversation_id,
                 turn_number,
                 prompt_file,
                 permission_mode,
                 mcp_config_path
               ) do
          try do
            session_id = "#{conversation_id}-turn-#{turn_number}"
            turn_id = "turn-#{turn_number}"

            emit_message(
              on_message,
              :session_started,
              %{
                session_id: session_id,
                thread_id: conversation_id,
                turn_id: turn_id
              },
              metadata
            )

            result =
              await_turn_completion(
                port,
                on_message,
                metadata,
                Config.claude_turn_timeout_ms(),
                Config.claude_stall_timeout_ms()
              )

            case result do
              {:ok, completion_payload} ->
                Logger.info("Claude session completed for #{issue_context(issue)} session_id=#{session_id}")

                {:ok,
                 %{
                   result: completion_payload,
                   session_id: session_id,
                   thread_id: conversation_id,
                   turn_id: turn_id
                 }}

              {:error, reason} ->
                if reason in [:turn_timeout, :stall_timeout] do
                  terminate_claude_process(metadata)
                end

                Logger.warning("Claude session failed for #{issue_context(issue)} session_id=#{session_id}: #{inspect(reason)}")

                {:error, reason}
            end
          after
            stop_port(port)
          end
        end
      after
        File.rm(prompt_file)
      end
    end
  end

  @spec stop_session(session()) :: :ok
  def stop_session(%{
        turn_counter: counter,
        mcp_config_path: mcp_config_path,
        cleanup_mcp_config?: cleanup_mcp_config?
      })
      when is_pid(counter) do
    try do
      Agent.stop(counter)
    catch
      :exit, _reason -> :ok
    end

    maybe_cleanup_mcp_config(mcp_config_path, cleanup_mcp_config?)
    :ok
  end

  def stop_session(%{mcp_config_path: mcp_config_path, cleanup_mcp_config?: cleanup_mcp_config?}) do
    maybe_cleanup_mcp_config(mcp_config_path, cleanup_mcp_config?)
    :ok
  end

  defp validate_workspace_cwd(workspace) when is_binary(workspace) do
    workspace_path = Path.expand(workspace)
    workspace_root = Path.expand(Config.workspace_root())

    root_prefix = workspace_root <> "/"

    cond do
      workspace_path == workspace_root ->
        {:error, {:invalid_workspace_cwd, :workspace_root, workspace_path}}

      not String.starts_with?(workspace_path <> "/", root_prefix) ->
        {:error, {:invalid_workspace_cwd, :outside_workspace_root, workspace_path, workspace_root}}

      true ->
        :ok
    end
  end

  defp resolve_permission_mode do
    case Config.claude_permission_mode() do
      permission_mode when is_binary(permission_mode) and permission_mode != "" ->
        {:ok, permission_mode}

      _ ->
        {:error, :missing_claude_permission_mode}
    end
  end

  defp mcp_config_for_session do
    case Config.claude_mcp_config() do
      path when is_binary(path) and path != "" ->
        {:ok, path, false}

      _ ->
        case McpConfig.write_temp(Workflow.workflow_file_path()) do
          {:ok, path} -> {:ok, path, true}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp next_turn_number(counter_pid) when is_pid(counter_pid) do
    turn_number =
      Agent.get_and_update(counter_pid, fn turn ->
        next = turn + 1
        {next, next}
      end)

    {:ok, turn_number}
  catch
    :exit, reason ->
      {:error, {:turn_counter_failed, reason}}
  end

  defp write_prompt_file(prompt) when is_binary(prompt) do
    prompt_path =
      Path.join(
        System.tmp_dir!(),
        "symphony-claude-prompt-#{System.unique_integer([:positive])}.txt"
      )

    case File.write(prompt_path, prompt) do
      :ok -> {:ok, prompt_path}
      {:error, reason} -> {:error, {:prompt_write_failed, reason}}
    end
  end

  defp start_port(
         workspace,
         conversation_id,
         turn_number,
         prompt_file,
         permission_mode,
         mcp_config_path
       ) do
    with {:ok, executable, command_args} <- claude_command_parts() do
      claude_args =
        command_args ++
          turn_args(conversation_id, turn_number) ++
          [
            "--print",
            "--verbose",
            "--output-format",
            "stream-json",
            "--permission-mode",
            permission_mode,
            "--model",
            Config.claude_model(),
            "--mcp-config",
            mcp_config_path
          ]

      shell_cmd =
        Enum.map_join([executable | claude_args], " ", &shell_escape/1) <>
          " < " <> shell_escape(prompt_file)

      port =
        Port.open(
          {:spawn, String.to_charlist(shell_cmd)},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:cd, String.to_charlist(workspace)},
            {:line, @port_line_bytes}
          ]
        )

      {:ok, port, port_metadata(port)}
    end
  end

  defp turn_args(conversation_id, 1), do: ["--session-id", conversation_id]
  defp turn_args(conversation_id, _turn_number), do: ["--resume", conversation_id]

  defp claude_command_parts do
    command = Config.claude_command() || ""
    tokens = OptionParser.split(command)

    case tokens do
      [raw_executable | args] ->
        with {:ok, executable} <- resolve_executable(raw_executable) do
          {:ok, executable, args}
        end

      [] ->
        {:error, :missing_claude_command}
    end
  end

  defp resolve_executable(raw_executable) do
    cond do
      raw_executable == "" ->
        {:error, :missing_claude_command}

      String.contains?(raw_executable, "/") ->
        {:ok, Path.expand(raw_executable)}

      true ->
        case System.find_executable(raw_executable) do
          nil -> {:error, {:claude_command_not_found, raw_executable}}
          executable -> {:ok, executable}
        end
    end
  end

  defp await_turn_completion(port, on_message, metadata, turn_timeout_ms, stall_timeout_ms) do
    start_ms = System.monotonic_time(:millisecond)
    turn_deadline_ms = start_ms + max(0, turn_timeout_ms)

    receive_loop(
      port,
      on_message,
      metadata,
      turn_deadline_ms,
      start_ms,
      max(0, stall_timeout_ms),
      "",
      []
    )
  end

  defp receive_loop(
         port,
         on_message,
         metadata,
         turn_deadline_ms,
         last_output_ms,
         stall_timeout_ms,
         pending_line,
         stderr_lines
       ) do
    now_ms = System.monotonic_time(:millisecond)
    turn_remaining_ms = turn_deadline_ms - now_ms

    stall_remaining_ms =
      case stall_timeout_ms do
        0 -> turn_remaining_ms
        timeout -> timeout - (now_ms - last_output_ms)
      end

    cond do
      turn_remaining_ms <= 0 ->
        {:error, :turn_timeout}

      stall_timeout_ms > 0 and stall_remaining_ms <= 0 ->
        {:error, :stall_timeout}

      true ->
        receive_timeout_ms = max(1, min(turn_remaining_ms, max(stall_remaining_ms, 1)))

        receive do
          {^port, {:data, {:eol, chunk}}} ->
            complete_line = pending_line <> to_string(chunk)
            next_output_ms = System.monotonic_time(:millisecond)

            handle_line_result =
              handle_stream_line(port, on_message, metadata, complete_line)

            case handle_line_result do
              {:continue, captured_line} ->
                receive_loop(
                  port,
                  on_message,
                  metadata,
                  turn_deadline_ms,
                  next_output_ms,
                  stall_timeout_ms,
                  "",
                  [captured_line | stderr_lines]
                )

              :continue ->
                receive_loop(
                  port,
                  on_message,
                  metadata,
                  turn_deadline_ms,
                  next_output_ms,
                  stall_timeout_ms,
                  "",
                  stderr_lines
                )

              {:ok, result_payload} ->
                {:ok, result_payload}

              {:error, reason} ->
                {:error, reason}
            end

          {^port, {:data, {:noeol, chunk}}} ->
            next_output_ms = System.monotonic_time(:millisecond)

            receive_loop(
              port,
              on_message,
              metadata,
              turn_deadline_ms,
              next_output_ms,
              stall_timeout_ms,
              pending_line <> to_string(chunk),
              stderr_lines
            )

          {^port, {:exit_status, 0}} ->
            {:error, {:turn_ended_without_result, build_exit_context(stderr_lines, pending_line)}}

          {^port, {:exit_status, status}} ->
            {:error, {:port_exit, status, build_exit_context(stderr_lines, pending_line)}}
        after
          receive_timeout_ms ->
            receive_loop(
              port,
              on_message,
              metadata,
              turn_deadline_ms,
              last_output_ms,
              stall_timeout_ms,
              pending_line,
              stderr_lines
            )
        end
    end
  end

  defp handle_stream_line(_port, on_message, metadata, line) do
    case StreamParser.parse_line(line) do
      {:ok, %{event: :turn_completed, payload: payload, usage: usage}} ->
        emit_message(on_message, :turn_completed, %{payload: payload, raw: line, usage: usage}, metadata)
        {:ok, payload}

      {:ok, %{event: :turn_failed, payload: payload}} ->
        emit_message(on_message, :turn_failed, %{payload: payload, raw: line}, metadata)
        {:error, {:turn_failed, payload}}

      {:ok, %{event: :notification, payload: payload}} ->
        emit_message(on_message, :notification, %{payload: payload, raw: line}, metadata)
        :continue

      {:error, :invalid_json} ->
        log_non_json_stream_line(line)
        emit_message(on_message, :malformed, %{payload: line, raw: line}, metadata)
        {:continue, line}
    end
  end

  defp terminate_claude_process(%{codex_app_server_pid: pid}) when is_binary(pid) do
    _ = System.cmd("kill", ["-9", pid])
    :ok
  end

  defp terminate_claude_process(_metadata), do: :ok

  defp maybe_cleanup_mcp_config(path, true), do: McpConfig.cleanup(path)
  defp maybe_cleanup_mcp_config(_path, false), do: :ok

  defp build_exit_context(stderr_lines, pending_line) do
    lines =
      stderr_lines
      |> Enum.reverse()
      |> Enum.concat([pending_line])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n")
    end
  end

  defp log_non_json_stream_line(data) do
    text =
      data
      |> to_string()
      |> String.trim()
      |> String.slice(0, @max_stream_log_bytes)

    if text != "" do
      if String.match?(text, ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i) do
        Logger.warning("Claude stream output: #{text}")
      else
        Logger.debug("Claude stream output: #{text}")
      end
    end
  end

  defp stop_port(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :ok

      _ ->
        try do
          Port.close(port)
          :ok
        rescue
          ArgumentError ->
            :ok
        end
    end
  end

  defp port_metadata(port) when is_port(port) do
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} ->
        %{codex_app_server_pid: Integer.to_string(os_pid)}

      _ ->
        %{}
    end
  end

  defp emit_message(on_message, event, details, metadata) when is_function(on_message, 1) do
    message =
      metadata
      |> Map.merge(details)
      |> Map.put(:event, event)
      |> Map.put(:timestamp, DateTime.utc_now())

    on_message.(message)
  end

  defp default_on_message(_message), do: :ok

  defp issue_context(%{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  defp shell_escape(arg) when is_binary(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end

  defp uuid_v4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = bor(band(c, 0x0FFF), 0x4000)
    d = bor(band(d, 0x3FFF), 0x8000)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
