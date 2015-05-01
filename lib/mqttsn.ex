defmodule Mqttsn do
  use Application

  def start(_type, _args) do
    Mqttsn.Supervisor.start_link
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

  def get_saved_data() do
    MProtocol.get_saved_data
  end
end
