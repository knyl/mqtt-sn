defmodule Mqttsn.ProtocolServerSup do
  use Supervisor

  def start_link(client_id, ip, port) do
    Supervisor.start_link(__MODULE__, [client_id, ip, port])
  end

  def init([client_id, ip, port]) do
    children = [
      worker(Connection.Udp, [{Mqttsn.ProtocolServer, :receive_data}, ip, port]),
      worker(Mqttsn.ProtocolServer, [client_id])]

    supervise(children, strategy: :one_for_all)
  end
end
