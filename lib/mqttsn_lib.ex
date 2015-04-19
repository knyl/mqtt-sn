defmodule MqttsnLib do
  use GenServer
  require Logger

  ## Public api: start/1, sub(topic), pub(topic, data)

   def start() do
     start_link({172,17,0,2}, 1884, [])
   end

  def start_link(ip, port, _opts \\ []) do
    GenServer.start_link(__MODULE__, %{ip: ip, port: port}, name: __MODULE__)
  end

  def subscribe(topic) do
    GenServer.call(__MODULE__, {:subscribe, topic})
  end

  def publish(topic, data) do
    GenServer.call(__MODULE__, {:publish, {topic, data}})
  end

  def register_topic(topic) do
    GenServer.call(__MODULE__, {:reg_topic, topic})
  end

  def receive_data(data) do
    GenServer.call(__MODULE__, {:receive_data, data})
  end

  ## Server callbacks

  def init(%{ip: ip, port: port}) do
    Logger.debug "Going to spawn process"
    pid = spawn(MqttsnConn, :start, [ip, port, {__MODULE__, :receive_data}])
    Logger.debug "Spawned communication process"
    socket = connect_to_broker(pid)
    topics = HashDict.new()
    {:ok, %{socket: socket, topics: topics, ip: ip, port: port, connection_pid:
        pid, connected: false, subscribe_message: [], reg_topic_status: []}}
  end

  def handle_call({:subscribe, topic}, _from, state) do
    true = state.connected # assert to make sure we're connected
    topic_data = prepare_topic_data(state.topics, topic)
    {:ok, updated_state} = subscribe_to_topic(topic_data, state)
    {:reply, :ok, updated_state}
  end

  def handle_call({:publish, {topic, data}}, _from, state) do
    true = state.connected # assert to make sure we're connected
    topic_data = prepare_topic_data(state.topics, topic)
    {:ok, updated_state} = publish_data(data, topic_data, state)
    {:reply, :ok, updated_state}
  end

  def handle_call({:reg_topic, topic}, _from, state) do
    true = state.connected # assert to make sure we're connected
    {:ok, updated_state} = reg_topic(topic, state)
    {:reply, :ok, updated_state}
  end

  def handle_call({:receive_data, data}, _from, state) do
    parsed_packet = Mqttsn.Message.decode(data)
    {:ok, updated_state} = handle_packet(parsed_packet, state)
    {:reply, :ok, updated_state}
  end

  #######################################################
  ## Handlers for different message types

  defp handle_packet({:sub_ack, response}, state) do
    :ok = response.return_code
    message_id = response.message_id
    Logger.debug "Received sub_ack for message_id #{message_id}"
    {^message_id, topic_data} = state.subscribe_message
    updated_topic_data = update_topic_data(topic_data, response.topic_id, state.topics)
    updated_state = %{state | topics: updated_topic_data, subscribe_message: []}
    {:ok, updated_state}
  end
  defp handle_packet({:conn_ack, status}, state) do
    Logger.debug "Received conn_ack with status #{inspect status}"
    # TODO: only handling status ok right now, no error handling
    :ok = status
    {:ok, %{state | connected: true}}
  end
  defp handle_packet({:publish, data}, state) do
    Logger.debug "Received publish with data #{inspect data}"
    {:ok, state}
  end
  defp handle_packet({:reg_ack, response}, state) do
    :ok = response.return_code
    message_id = response.message_id
    Logger.debug "Received reg_ack for message_id #{message_id}"
    {^message_id, topic} = state.reg_topic_status
    updated_topic_data = HashDict.put(state.topics, topic, response.topic_id)
    updated_state = %{state | topics: updated_topic_data, reg_topic_status: []}
    {:ok, updated_state}
  end
  defp handle_packet({:pub_ack, response}, state) do
    status = response.return_code
    Logger.debug "Received pub_ack with status #{inspect status}"
    {:ok, state}
  end

  defp publish_data(data, topic_data, state) do
    {publish_packet, {_message_id, _topic_data}} = publish_packet(topic_data, data)
    pid = state.connection_pid
    send(pid, {:send, publish_packet})
    {:ok, state}
  end

  defp reg_topic(topic, state) do
    {reg_packet, register_topic_info} = reg_topic_packet(topic)
    pid = state.connection_pid
    send(pid, {:send, reg_packet})
    updated_state = %{state | reg_topic_status: {register_topic_info, topic}}
    {:ok, updated_state}
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

  defp prepare_topic_data(topics, topic) do
    Logger.debug "Searching for topic #{inspect topic}"
    case HashDict.has_key?(topics, topic) do
      true  ->
        topic_id = HashDict.get(topics, topic)
        Logger.debug "Topic was found, id: #{topic_id}"
        {:topic_id, topic_id}
      false ->
        Logger.debug "Topic was not found"
        {:topic_name, topic}
    end
  end

  defp publish_packet(topic_data, data) do
    type = Mqttsn.message_type(:publish)
    Logger.debug "Topic data #{inspect topic_data}"
    flags = topic_flags(topic_data)
    # TODO: Only QoS 0 so far, thus message_id 0x0000
    message_id = 0
    topic = get_topic_data(topic_data)
    Logger.debug "Publishing on topic: #{inspect topic}"
    #Logger.debug "Data to be published: #{inspect data}"
    Logger.debug "Data is binary: #{inspect is_binary(data)}"
    data_length = byte_size(data)
    length = 7 + data_length
    {<<length::8, type::8, flags::8, topic::16, message_id::16,
      data::binary>>, {message_id, topic_data}}
  end

  defp reg_topic_packet(raw_topic_name) do
    type = Mqttsn.message_type(:reg_topic)
    message_id = get_message_id()
    topic_id = 0
    topic_name = :erlang.term_to_binary(raw_topic_name)
    topic_length = byte_size(topic_name)
    length = 6 + topic_length
    {<<length::8, type::8, topic_id::16, message_id::16, topic_name::binary>>,
      message_id}
  end

  defp subscribe_packet(topic_data) do
    type  = Mqttsn.message_type(:subscribe)
    flags = topic_flags(topic_data)
    message_id = get_message_id()
    topic = :erlang.term_to_binary(get_topic_data(topic_data))
    topic_length = byte_size(topic)
    length = 5 + topic_length
    ## TODO: fix length here, can be variable
    {<<length::8, type::8, flags::8, message_id::16, topic::binary>>,
      {message_id, topic_data}}
  end

  defp topic_flags({:topic_id, _topic}) do
    0b00
  end
  defp topic_flags({:topic_name, _topic}) do
    0b10
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
    Logger.debug "Sent connect package to broker"
  end

  defp connect_packet(client_id) do
    Logger.debug "Connecting with client_id #{client_id}"
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
