defmodule SymphonyElixir.Backend do
  @moduledoc """
  Behaviour contract for agent execution backends.
  """

  @type session :: map()

  @callback start_session(Path.t()) :: {:ok, session()} | {:error, term()}
  @callback run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stop_session(session()) :: :ok
end
