MqttsnLib
=========

A library, written in Elixir,  implementing the MQTT-SN protocol for
sensor networks.

** Working Features **

- only QoS 0 so far
- connect
- subscribe to topic

** Usage **

```
{:ok, pid} = MqttsnLib:start_link(ip, port, opts)
MqttsnLib.subscribe(pid, topic)
```

** TODO **

- Publish
- Receive data
- All the things..

