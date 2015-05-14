defmodule Mqttsn do
  use Application

  def start(_type, _args) do
    client_id = Application.get_env(:mqttsn, :client_id)
    ip = Application.get_env(:mqttsn, :ip)
    port = Application.get_env(:mqttsn, :port)
    Mqttsn.Supervisor.start_link([client_id, ip, port])
  end

  def subscribe(topic) do
    Mqttsn.ProtocolServer.subscribe(topic)
  end

  def publish(topic, data) do
    Mqttsn.ProtocolServer.publish(topic, data)
  end

  def register_topic(topic) do
    Mqttsn.ProtocolServer.register_topic(topic)
  end

  def receive_data(data) do
    Mqttsn.ProtocolServer.receive_data(data)
  end

  def register_listener(module, function) do
    Mqttsn.ProtocolServer.register_listener(module, function)
  end
end
