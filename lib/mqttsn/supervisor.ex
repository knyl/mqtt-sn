defmodule Mqttsn.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init([client_id, ip, port]) do
    children = [
      worker(Connection.Udp, [{Mqttsn.ProtocolServer, :receive_data}, ip, port]),
      worker(Mqttsn.ProtocolServer, [client_id])]

    supervise(children, strategy: :one_for_all)
  end
end
