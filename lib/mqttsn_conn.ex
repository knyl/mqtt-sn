defmodule MqttsnConn do
  require Logger

   def start(ip, port, {module, function}) do
     {:ok, socket} = connect(port)
     loop(%{ip: ip, port: port, socket: socket, callback_info: {module, function}})
   end

  defp connect(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    Logger.info "Accepting connections on port #{port}"
    {:ok, socket}
  end

  defp loop(state) do
    receive do
      {:udp, _socket, _ip, _in_port_no, packet} ->
        {module, function} = state.callback_info
        apply(module, function, [packet])
      {:send, data} ->
        :ok = :gen_udp.send(state.socket, state.ip, state.port, data)
      _ ->
        :ok
    end
    loop(state)
  end

end
