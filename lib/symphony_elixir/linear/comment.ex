defmodule SymphonyElixir.Linear.Comment do
  @moduledoc """
  Normalized Linear comment representation.
  """

  defstruct [:id, :body, :user_id, :user_name, :created_at, :updated_at]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          body: String.t() | nil,
          user_id: String.t() | nil,
          user_name: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
