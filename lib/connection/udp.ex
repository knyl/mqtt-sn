defmodule Connection.Udp do
  require Logger

   def start_link({module, function}) do
    GenServer.start_link(__MODULE__, {module, function}, name: __MODULE__)
   end

   def send_data(data) do
     GenServer.call(__MODULE__, {:send, data})
   end

   def init({module, function}) do
     ip = Application.get_env(:mqttsn_lib, :ip)
     port = Application.get_env(:mqttsn_lib, :port)
     {:ok, socket} = connect(port)
     Logger.info "Connection.Udp has started"
     {:ok, %{ip: ip, port: port, socket: socket, callback_info: {module, function}}}
   end

   def handle_call({:send, data}, _from, state) do
      :ok = :gen_udp.send(state.socket, state.ip, state.port, data)
      {:reply, :ok, state}
   end

   def handle_info({:udp, _socket, ip, _in_port_no, packet}, state) do
     Logger.debug "Received an udp packet from #{inspect ip}"
      {module, function} = state.callback_info
      apply(module, function, [packet])
      {:noreply, state}
   end

  defp connect(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    Logger.debug "Accepting connections on port #{port}"
    {:ok, socket}
  end

end
