defmodule Mqttsn.Message do

  @doc """
  Decodes a MQTT-SN binary packet into a tuple
  """
  def decode(<<0x01::8, length::16, type::8, message::binary>>) do
    decode_with_header(Mqttsn.Constants.message_type(type), length, message)
  end

  def decode(<<length::8, type::8,  message::binary>>) do
    decode_with_header(Mqttsn.Constants.message_type(type), length, message)
  end

  def encode({:subscribe, data}) do
    encode_subscribe(data)
  end
  def encode({:reg_topic, data}) do
    encode_reg_topic(data)
  end
  def encode({:publish, data}) do
    encode_publish(data)
  end
  def encode({:connect, data}) do
    encode_connect(data)
  end

  ## Decode functions

  defp decode_with_header(:conn_ack, _length, <<raw_return_code::8>>) do
    return_code = Mqttsn.Constants.return_code(raw_return_code)
    {:conn_ack, return_code}
  end
  defp decode_with_header(:sub_ack, _length, data) do
    decode_sub_ack(data)
  end
  defp decode_with_header(:reg_ack, _length, data) do
    decode_reg_ack(data)
  end
  defp decode_with_header(:publish, _length, data) do
    decode_publish(data)
  end
  defp decode_with_header(:pub_ack, _length, data) do
    decode_pub_ack(data)
  end

  defp decode_sub_ack(<<_flags::8, topic_id::16, message_id::16, raw_return_code::8 >>) do
    return_code = Mqttsn.Constants.return_code(raw_return_code)
    {:sub_ack, %{topic_id: topic_id, message_id: message_id, return_code: return_code}}
  end

  defp decode_reg_ack(<<topic_id::16, message_id::16, raw_return_code::8>>) do
    return_code = Mqttsn.Constants.return_code(raw_return_code)
    {:reg_ack, %{topic_id: topic_id, message_id: message_id, return_code: return_code}}
  end

  defp decode_publish(<<_flags::8, topic_id::16, message_id::16, data::binary>>) do
    {:publish, %{topic_id: topic_id, message_id: message_id, data: data}}
  end

  defp decode_pub_ack(<<topic_id::16, message_id::16, raw_return_code::8 >>) do
    return_code = Mqttsn.Constants.return_code(raw_return_code)
    {:pub_ack, %{topic_id: topic_id, message_id: message_id, return_code: return_code}}
  end

  ## Encode functions

  defp encode_connect(%{flags: flags, client_id: client_id}) do
    length = 8
    msg_type = Mqttsn.Constants.message_type(:connect)
    protocol_id = Mqttsn.Constants.protocol_id()
    duration = 0x09
    <<length::8, msg_type::8, flags::8, protocol_id::8, duration::16, client_id::16>>
  end

  defp encode_subscribe(%{message_id: message_id, topic: topic, flags: flags}) do
    type = Mqttsn.Constants.message_type(:subscribe)
    length = 5 + byte_size(topic)
    <<length::8, type::8, flags::8, message_id::16, topic::binary>>
  end

  defp encode_reg_topic(%{message_id: message_id, topic_name: raw_topic_name}) do
    type = Mqttsn.Constants.message_type(:reg_topic)
    topic_id = 0
    topic_name = :erlang.term_to_binary(raw_topic_name)
    length = 6 + byte_size(topic_name)
    <<length::8, type::8, topic_id::16, message_id::16, topic_name::binary>>
  end

  defp encode_publish(data) do
    type = Mqttsn.Constants.message_type(:publish)
    flags = data.flags
    topic = data.topic
    message_id = data.message_id
    message = data.message
    length = 7 + byte_size(message)
    <<length::8, type::8, flags::8, topic::16, message_id::16, message::binary>>
  end

end
