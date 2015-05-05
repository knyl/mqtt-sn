defmodule Mqttsn do
  use Application

  def start(_type, _args) do
    client_id = Application.get_env(:mqttsn, :client_id)
    ip = Application.get_env(:mqttsn, :ip)
    port = Application.get_env(:mqttsn, :port)
    Mqttsn.Supervisor.start_link([client_id, ip, port])
  end

  def subscribe(topic) do
    MProtocol.subscribe(topic)
  end

  def publish(topic, data) do
    MProtocol.publish(topic, data)
  end

  def register_topic(topic) do
    MProtocol.register_topic(topic)
  end

  def receive_data(data) do
    MProtocol.receive_data(data)
  end

  def register_listener({module, function}) do
    MProtocol.register_listener({module, function})
  end
end
