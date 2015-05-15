defmodule Mqttsn.State do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add_listener(module, function) do
    GenServer.call(__MODULE__, {:add_listener, {module, function}})
  end

  def get_listeners() do
    GenServer.call(__MODULE__, :get_listeners)
  end

  def add_topic_subscription(topic) do
    GenServer.call(__MODULE__, {:add_subscription, topic})
  end

  def get_stored_subscriptions() do
    GenServer.call(__MODULE__, :get_subscriptions)
  end

  def init([]) do
    {:ok, %{listeners: [], topics: []}}
  end

  def handle_call({:add_listener, {module, function}}, _from, state) do
    listeners = [{module, function} | state.listeners]
    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call(:get_listeners, _from, state) do
    {:reply, {:ok, state.listeners}, state}
  end

  def handle_call({:add_subscription, topic}, _from, state) do
    {:reply, :ok, %{state | topics: [topic | state.topics]}}
  end

  def handle_call(:get_subscriptions, _from, state) do
    {:reply, {:ok, state.topics}, state}
  end

end
