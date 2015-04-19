MqttsnLib
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

```
{:ok, pid} = MqttsnLib:start_link(ip, port, opts)
MqttsnLib.subscribe(pid, topic)
```

** TODO **

- Better/more logging
- Start application and processes in a proper way
- Handle QoS properly (add to configuration? fail if non-implemented QoS is
    requested)
- Error handling
- Proper message id
- Proper client id
- Proper internal data structure
- Tests!!
- All the things..

