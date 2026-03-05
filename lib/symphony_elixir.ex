defmodule SymphonyElixir do
  @moduledoc """
  Entry point for the Symphony orchestrator.
  """

  @doc """
  Start the orchestrator in the current BEAM node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    SymphonyElixir.Orchestrator.start_link(opts)
  end
end

defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = SymphonyElixir.LogFile.configure()

    case validate_required_env_vars() do
      :ok ->
        children = [
          {Phoenix.PubSub, name: SymphonyElixir.PubSub},
          {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
          SymphonyElixir.WorkflowStore,
          SymphonyElixir.Orchestrator,
          SymphonyElixir.HttpServer,
          SymphonyElixir.StatusDashboard
        ]

        Supervisor.start_link(
          children,
          strategy: :one_for_one,
          name: SymphonyElixir.Supervisor
        )

      {:error, message} ->
        IO.puts(:stderr, "Startup failed: #{message}")
        {:error, message}
    end
  end

  defp validate_required_env_vars do
    with :ok <- check_linear_api_key(),
         :ok <- check_openai_api_key() do
      :ok
    end
  end

  defp check_linear_api_key do
    case System.get_env("LINEAR_API_KEY") do
      nil -> {:error, "LINEAR_API_KEY environment variable is not set"}
      "" -> {:error, "LINEAR_API_KEY environment variable is empty"}
      _ -> :ok
    end
  end

  defp check_openai_api_key do
    case System.get_env("OPENAI_API_KEY") do
      nil -> {:error, "OPENAI_API_KEY environment variable is not set"}
      "" -> {:error, "OPENAI_API_KEY environment variable is empty"}
      _ -> :ok
    end
  end

  @impl true
  def stop(_state) do
    SymphonyElixir.StatusDashboard.render_offline_status()
    :ok
  end
end
