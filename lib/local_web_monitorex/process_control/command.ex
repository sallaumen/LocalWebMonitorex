defmodule LocalWebMonitorex.ProcessControl.Command do
  @moduledoc false

  @timeout 2_000

  @spec terminate(String.t(), [String.t()], (String.t(), [String.t()] -> tuple())) ::
          :ok | {:error, atom()}
  def terminate(command, args, runner) do
    case runner.(command, args) do
      {_output, 0} -> :ok
      {:error, reason} -> {:error, reason}
      {_output, _status} -> {:error, :command_failed}
    end
  end

  @spec run(String.t(), [String.t()]) :: {String.t(), non_neg_integer()} | {:error, atom()}
  def run(command, args) do
    task = Task.async(fn -> execute(command, args) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp execute(command, args) do
    System.cmd(command, args, stderr_to_stdout: true)
  rescue
    _error in [ErlangError, ArgumentError] -> {:error, :command_unavailable}
  end
end
