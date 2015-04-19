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
    pid = spawn(Connection.Udp, :start, [ip, port, {__MODULE__, :receive_data}])
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
    {^message_id, topic} = state.subscribe_message
    updated_topic_data = HashDict.put(state.topics, topic, response.topic_id)
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

  defp publish_data(message, topic_data, state) do
    Logger.debug "Publishing on topic: #{inspect topic_data.topic}"
    message_id = get_message_id()
    flags = Mqttsn.Constants.topic_flag(topic_data.type)
    data = %{message_id: message_id, flags: flags, topic: topic_data.topic, message: message}
    publish_packet = Mqttsn.Message.encode({:publish, data})
    pid = state.connection_pid
    send(pid, {:send, publish_packet})
    {:ok, state}
  end

  defp reg_topic(topic_name, state) do
    message_id = get_message_id()
    data = %{message_id: message_id, topic_name: topic_name}
    reg_packet = Mqttsn.Message.encode({:reg_topic, data})
    pid = state.connection_pid
    send(pid, {:send, reg_packet})
    updated_state = %{state | reg_topic_status: {message_id, topic_name}}
    {:ok, updated_state}
  end

  defp subscribe_to_topic(topic, state) do
    flags = Mqttsn.Constants.topic_flag(topic.type)
    message_id = get_message_id()
    data = %{message_id: message_id, topic: topic.topic, flags: flags}
    subscribe_packet = Mqttsn.Message.encode({:subscribe, data})
    pid = state.connection_pid
    send(pid, {:send, subscribe_packet})
    updated_state = %{state | subscribe_message: {message_id, topic}}
    {:ok, updated_state}
  end

  defp prepare_topic_data(topics, topic) do
    Logger.debug "Searching for topic #{inspect topic}"
    case HashDict.has_key?(topics, topic) do
      true  ->
        topic_id = HashDict.get(topics, topic)
        Logger.debug "Topic was found, id: #{topic_id}"
        %{type: :topic_name, topic: topic_id}
      false ->
        Logger.debug "Topic was not found"
        %{type: :topic_name, topic: topic}
    end
  end

  defp get_message_id() do
    10
  end

  defp connect_to_broker(pid) do
    client_id = 16
    Logger.debug "Connecting with client_id #{client_id}"
    flags = 0
    data = %{flags: flags, client_id: client_id}
    connect_packet = Mqttsn.Message.encode({:connect, data})
    send(pid, {:send, connect_packet})
    Logger.debug "Sent connect package to broker"
  end

end
