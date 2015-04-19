defmodule MqttsnParser do

  def parse(<<0x01::8, length::16, type::8, message::binary>>) do
    parse_with_header(Mqttsn.message_type(type), length, message)
  end

  def parse(<<length::8, type::8,  message::binary>>) do
    parse_with_header(Mqttsn.message_type(type), length, message)
  end

  defp parse_with_header(:conn_ack, _length, <<raw_return_code::8>>) do
    return_code = Mqttsn.return_code(raw_return_code)
    {:conn_ack, return_code}
  end
  defp parse_with_header(:sub_ack, _length, data) do
    parse_sub_ack(data)
  end
  defp parse_with_header(:reg_ack, _length, data) do
    parse_reg_ack(data)
  end
  defp parse_with_header(:publish, _length, data) do
    parse_publish(data)
  end
  defp parse_with_header(:pub_ack, _length, data) do
    parse_pub_ack(data)
  end

  defp parse_sub_ack(<<_flags::8, topic_id::16, message_id::16, raw_return_code::8 >>) do
    return_code = Mqttsn.return_code(raw_return_code)
    {:sub_ack, %{topic_id: topic_id, message_id: message_id, return_code: return_code}}
  end

  defp parse_reg_ack(<<topic_id::16, message_id::16, raw_return_code::8>>) do
    return_code = Mqttsn.return_code(raw_return_code)
    {:reg_ack, %{topic_id: topic_id, message_id: message_id, return_code: return_code}}
  end

  defp parse_publish(<<_flags::8, topic_id::16, message_id::16, data::binary>>) do
    {:publish, %{topic_id: topic_id, message_id: message_id, data: data}}
  end

  defp parse_pub_ack(<<topic_id::16, message_id::16, raw_return_code::8 >>) do
    return_code = Mqttsn.return_code(raw_return_code)
    {:pub_ack, %{topic_id: topic_id, message_id: message_id, return_code: return_code}}
  end

end
