defmodule MProtocol do
  use GenServer
  require Logger

  ## Public api

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
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

  def register_listener(module, function) do
    GenServer.call(__MODULE__, {:register_listener, {module, function}})
  end

  ## Server callbacks

  def init(client_id) do
    :inets.start()
    socket = connect_to_broker(client_id)
    topics = HashDict.new()
    {:ok, %{socket: socket, topics: topics, connected: false,
            subscribe_message: [], reg_topic_status: [], listeners: [],
            client_id: client_id, stored_until_connect: []}}
  end

  def handle_call({:subscribe, topic}, _from, state) do
    topic_data = prepare_topic_data(state.topics, topic)
    updated_state =
      case state.connected do
        false ->
          %{state | stored_until_connect: [{:subscribe, topic_data} | state.stored_until_connect]}
        true  ->
          {:ok, updated_state} = subscribe_to_topic(topic_data, state)
          updated_state
      end
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

  def handle_call({:register_listener, {module, function}}, _from, state) do
    updated_listeners = [{module, function} | state.listeners]
    updated_state = %{state | listeners: updated_listeners}
    {:reply, :ok, updated_state}
  end

  def terminate(reason, _state) do
    # mqtt-sn termination here
    Logger.info "Mqtt is shutting down due to reason: #{inspect reason}"
  end

  #######################################################
  ## Handlers for different message types

  defp handle_packet({:sub_ack, response}, state) do
    :ok = response.return_code
    message_id = response.message_id
    Logger.debug "Received sub_ack for message_id #{message_id}"
    {^message_id, topic} = state.subscribe_message
    Logger.debug "Topic id is #{inspect response.topic_id}"
    updated_topic_data = HashDict.put(state.topics, topic, response.topic_id)
    updated_state = %{state | topics: updated_topic_data, subscribe_message: []}
    {:ok, updated_state}
  end
  defp handle_packet({:conn_ack, status}, state) do
    Logger.debug "Received conn_ack with status #{inspect status}"
    :ok = status
    # TODO: only handling status ok right now, no error handling
    ops = state.stored_until_connect
    subscribe_fun =
      fn({:subscribe, topic}, acc_state) ->
        {:ok, new_acc} = subscribe_to_topic(topic, acc_state)
        new_acc
      end
    updated_state = List.foldl(ops, state, subscribe_fun)
    {:ok, %{updated_state | connected: true, stored_until_connect: []}}
  end
  defp handle_packet({:publish, data}, state) do
    # TODO: This only handles integers that should be converted to floats right
    # now
    Logger.debug "Received publish with data #{inspect data}"
    <<raw_temperature::32-integer-signed-little, time::32>> = data.data
    temperature = raw_temperature / 100
    Logger.info "Received data: #{inspect temperature} at time #{time}"
    send_to_listeners(temperature, state.listeners)
    {:ok, state}
  end
  defp handle_packet({:reg_ack, response}, state) do
    :ok = response.return_code
    message_id = response.message_id
    Logger.debug "Received reg_ack for message_id #{message_id}"
    Logger.debug "Topic id is #{response.topic_id}"
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
  defp handle_packet({:reg_topic, data}, state) do
    Logger.debug "Got register topic"
    Logger.debug "Topic_id: #{data.topic_id}"
    Logger.debug "Topic_name: #{data.topic_name}"
    updated_topic_data = HashDict.put(state.topics, data.topic_name, data.topic_id)

    return_code = Mqttsn.Constants.return_code(:ok)
    data = %{message_id: data.message_id, topic_id: data.topic_id, return_code: return_code}
    reg_ack_packet = Mqttsn.Message.encode({:reg_ack, data})
    send_data(reg_ack_packet)

    updated_state = %{state | topics: updated_topic_data}
    {:ok, updated_state}
  end
  defp handle_packet({message, _response}, state) do
    Logger.debug "Got unknown message #{inspect message}"
    {:ok, state}
  end


  defp publish_data(message, topic_data, state) do
    Logger.debug "Publishing on topic: #{inspect topic_data.topic}"
    message_id = get_message_id()
    flags = %{topic_id_type: Mqttsn.Constants.topic_flag(topic_data.type)}
    data = %{message_id: message_id, flags: flags, topic: topic_data.topic, message: message}
    publish_packet = Mqttsn.Message.encode({:publish, data})
    send_data(publish_packet)
    {:ok, state}
  end

  defp reg_topic(topic_name, state) do
    message_id = get_message_id()
    data = %{message_id: message_id, topic_name: topic_name}
    reg_packet = Mqttsn.Message.encode({:reg_topic, data})
    send_data(reg_packet)
    updated_state = %{state | reg_topic_status: {message_id, topic_name}}
    {:ok, updated_state}
  end

  defp subscribe_to_topic(topic, state) do
    flags = %{topic_id_type: Mqttsn.Constants.topic_flag(topic.type)}
    message_id = get_message_id()
    data = %{message_id: message_id, topic: topic.topic, flags: flags}
    Logger.debug "Subscribing to topic: #{topic.topic}"
    subscribe_packet = Mqttsn.Message.encode({:subscribe, data})
    send_data(subscribe_packet)
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

  defp connect_to_broker(client_id) do
    Logger.debug "Connecting with client_id #{client_id}"
    flags = %{clean_session: Mqttsn.Constants.clean_session_flag(true)}
    data = %{flags: flags, client_id: client_id}
    connect_packet = Mqttsn.Message.encode({:connect, data})
    send_data(connect_packet)
    Logger.debug "Sent connect package to broker"
  end

  defp send_data(packet) do
    Logger.debug "Data to be sent: #{inspect packet}"
    Connection.Udp.send_data(packet)
  end

  defp send_to_listeners(data, listeners) do
    for {module, function} <- listeners, do: apply(module, function, [data])
  end
end
