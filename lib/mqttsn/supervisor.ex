defmodule Mqttsn.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Connection.Udp, [{MProtocol, :receive_data}]),
      worker(MProtocol, [])]

    supervise(children, strategy: :one_for_all)
  end
end
