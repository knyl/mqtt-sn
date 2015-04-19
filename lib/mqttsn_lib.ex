defmodule MqttsnLib do
  use GenServer
  require Logger

  ## Public api: start/1, sub(topic), pub(topic, data)

   def start() do
     start_link({172,17,0,2}, 1884, [])
   end

  def start_link(ip, port, opts \\ []) do
    GenServer.start_link(__MODULE__, %{ip: ip, port: port}, opts)
  end

  def subscribe(server, topic) do
    GenServer.call(server, {:subscribe, topic})
  end

  def publish(server, topic, data) do
    GenServer.call(server, {:publish, {topic, data}})
  end

  def register_topic(server, topic, _data) do
    GenServer.call(server, {:reg_topic, topic})
  end

  def receive_data(server, data) do
    GenServer.call(server, {:receive_data, data})
  end

  ## Server callbacks

  def init(%{ip: ip, port: port}) do
    Logger.info "Going to spawn process"
    pid = spawn(MqttsnConn, :start, [ip, port, {__MODULE__, :receive_data, self()}])
    Logger.info "Spawned communication process"
    socket = connect_to_broker(pid)
    topics = HashDict.new()
    {:ok, %{socket: socket, topics: topics, ip: ip, port: port, connection_pid:
        pid, connected: false, subscribe_message: []}}
  end

  def handle_call({:subscribe, topic}, _from, state) do
    true = state.connected # assert to make sure we're connected
    registered_topics = state.topics
    topic_data = case HashDict.has_key?(registered_topics, topic) do
      true  ->
        {:topic_id, HashDict.get(registered_topics, topic)}
      false ->
        {:topic_name, topic}
    end
    {:ok, updated_state} = subscribe_to_topic(topic_data, state)
    {:reply, :ok, updated_state}
  end

  def handle_call({:publish, {_topic, _data}}, _from, state) do
    true = state.connected # assert to make sure we're connected
    {:reply, [], state}
  end

  def handle_call({:reg_topic, _topic}, _from, state) do
    true = state.connected # assert to make sure we're connected
    {:reply, :ok, state}
  end

  def handle_call({:receive_data, data}, _from, state) do
    parsed_packet = MqttsnParser.parse(data)
    {:ok, updated_state} = handle_packet(parsed_packet, state)
    {:reply, :ok, updated_state}
  end

  defp handle_packet({:sub_ack, response}, state) do
    :ok = response.return_code
    message_id = response.message_id
    {^message_id, topic_data} = state.subscribe_message
    updated_topic_data = update_topic_data(topic_data, response.topic_id, state.topics)
    updated_state = %{state | topics: updated_topic_data, subscribe_message: []}
    {:ok, updated_state}
  end
  defp handle_packet({:conn_ack, :ok}, state) do
    {:ok, %{state | connected: true}}
  end

  defp subscribe_to_topic(topic_data, state) do
    {subscribe_packet, subscribe_info} = subscribe_packet(topic_data)
    pid = state.connection_pid
    send(pid, {:send, subscribe_packet})
    updated_state = %{state | subscribe_message: subscribe_info}
    {:ok, updated_state}
  end

  defp update_topic_data({:topic_id, _}, _, topics) do
    topics
  end
  defp update_topic_data({:topic_name, topic}, topic_id, topics) do
    HashDict.put(topics, topic, topic_id)
  end

  defp subscribe_packet(topic_data) do
    type  = Mqttsn.message_type(:subscribe)
    flags = subscribe_flags(topic_data)
    message_id = get_message_id()
    topic = :erlang.term_to_binary(get_topic_data(topic_data))
    topic_length = byte_size(topic)
    length = 5 + topic_length
    ## TODO: fix length here, can be variable
    {<<length::8, type::8, flags::8, message_id::16, topic::binary>>,
      {message_id, topic_data}}
  end

  defp subscribe_flags({:topic_id, _topic}) do
    0x0b01
  end
  defp subscribe_flags({:topic_name, _topic}) do
    0x0b00
  end

  defp get_message_id() do
    10
  end

  defp get_topic_data({_topic_type, topic}) do
    topic
  end

  defp connect_to_broker(pid) do
    connect_packet = connect_packet(16)
    send(pid, {:send, connect_packet})
    Logger.info "Sent connect package to broker"
  end

  defp connect_packet(client_id) do
    Logger.info "Connecting with client_id #{client_id}"
    length = 8
    msg_type = Mqttsn.message_type(:connect)
    flags = 0
    protocol_id = Mqttsn.protocol_id()
    duration = 0x09
    message = <<length::8, msg_type::8, flags::8, protocol_id::8,
                duration::16, client_id::16>>
    message
  end

end
