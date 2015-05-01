defmodule MqttsnLib do
  use GenServer
  require Logger

  ## Public api: start/1, sub(topic), pub(topic, data)

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
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

  def get_saved_data() do
    GenServer.call(__MODULE__, :get_saved_data)
  end

  ## Server callbacks

  def init(_args) do
    :inets.start()
    socket = connect_to_broker()
    topics = HashDict.new()
    {ok, table_name} = :dets.open_file(:temperature_data_backup, [])
    {:ok, %{socket: socket, topics: topics, connected: false,
            subscribe_message: [], reg_topic_status: [], dets: table_name}}
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

  def handle_call(:get_saved_data, _from, state) do
    match_pattern = :'$1'
    data = :dets.match(state.dets, match_pattern)
    {:reply, data, state}
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
    # TODO: only handling status ok right now, no error handling
    :ok = status
    {:ok, %{state | connected: true}}
  end
  defp handle_packet({:publish, data}, state) do
    Logger.debug "Received publish with data #{inspect data}"
    <<raw_temperature::32-integer-signed-little, time::32>> = data.data
    temperature = raw_temperature / 100
    Logger.info "Received temperature: #{inspect temperature} at time #{time}"

    send_data_to_kibana(temperature, state)
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

  defp connect_to_broker() do
    client_id = 16
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

  def send_data_to_kibana(temperature, state) do
    now = :calendar.universal_time()
    send_data_to_kibana(temperature, now, state)
  end

  defp send_data_to_kibana(temperature, time, state) do
    {{year, month, day}, _} = time
    date = List.flatten(:io_lib.format("~4.10.0B.~2.10.0B.~2.10.0B", [year, month, day]))
    Logger.debug "Date: #{date}"
    url_b = Enum.join(['http://localhost/logstash-', date, '/entry'])
    url = :erlang.binary_to_list(url_b)
    username = "foo"
    password = "foo"
    auth_string = Enum.join([username, ":", password])
    headers = [{'Authorization',
                :erlang.binary_to_list(Enum.join(['Basic ', :base64.encode_to_string(auth_string)]))}]
    #headers = :erlang.binary_to_list(headers_b)
    content_type = 'Application/json'
    timestamp = iso_8601_fmt(time)
    location = "knyppeldynan"
    device = "balcony_green_house_01"
    body_b = Enum.join(["{ \"timestamp\": \"", timestamp, "\", \"location\": \"", location,
                        "\", \"device\": \"", device, "\", \"temp_01\": ", temperature, "}"])
    body = :erlang.binary_to_list(body_b)
    Logger.debug "Going to send request: "
    Logger.debug "Url: #{url}"
    Logger.debug "Body: #{body}"
    Logger.debug "Headers: #{inspect headers}"
    {ok, result} = :httpc.request(:post, {url, headers, content_type, body}, [], [])
    Logger.debug "Got result #{inspect result}"
    case result do
      {{_, 502, _}, _, _} -> save_data_locally(temperature, time, state.dets)
      {{_, 201, _}, _, _} -> :ok
      error_result -> Logger.debug "Got error result #{inspect error_result}"
    end
  end

  defp iso_8601_fmt(date_time) do
    {{year, month, day},{hour, min, sec}} = date_time
    :io_lib.format("~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",
                   [year, month, day, hour, min, sec])
  end

  def save_data_locally(temperature, time, table_name) do
    result = :dets.insert(table_name, {temperature, time})
    Logger.debug "Inserting {#{temperature}, #{inspect time}} into dets with result #{inspect result}"
    :ok
  end


end
