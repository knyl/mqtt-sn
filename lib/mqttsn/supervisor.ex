defmodule Mqttsn.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init([client_id, ip, port]) do
    children = [
      worker(Mqttsn.ProtocolServerSup, [client_id, ip, port]),
      worker(Mqttsn.StateSup, [])]

    supervise(children, strategy: :one_for_one)
  end
end
