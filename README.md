Mqttsn
=========

A library, written in Elixir,  implementing the MQTT-SN protocol for
sensor networks.

** Working Features **

- only QoS 0 so far
- connect
- subscribe to topic
- register topic
- publish

** Usage **

Update `config/config.exs` with your rsmb broker information (ip, port).


```
iex> Mqttsn.subscribe(topic_name)
iex> Mqttsn.register_topic(topic_name)

iex> Mqttsn.publish(topic_name, binary_data)
```

** TODO **

- Better/more logging
- Handle QoS properly (add to configuration? fail if non-implemented QoS is
    requested)
- Error handling
- Proper message id
- Proper client id
- Proper internal data structure
- Tests!!
- All the things..

