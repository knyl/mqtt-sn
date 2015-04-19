defmodule Mqttsn.Constants do

  def protocol_id() do
    0x01
  end

  def topic_flag(:topic_name) do
    0b00
  end
  def topic_flag(:topic_id) do
    0b01
  end
  def topic_flag(:topic_short_name) do
    0b10
  end

  def message_type(:connect) do
    0x04
  end
  def message_type(0x04) do
    :connect
  end
  def message_type(:conn_ack) do
    0x05
  end
  def message_type(0x05) do
    :conn_ack
  end
  def message_type(:subscribe) do
    0x12
  end
  def message_type(0x12) do
    :subscribe
  end
  def message_type(:sub_ack) do
    0x13
  end
  def message_type(0x13) do
    :sub_ack
  end
  def message_type(:reg_topic) do
    0x0A
  end
  def message_type(0x0A) do
    :reg_topic
  end
  def message_type(:reg_ack) do
    0x0B
  end
  def message_type(0x0B) do
    :reg_ack
  end
  def message_type(:publish) do
    0x0C
  end
  def message_type(0x0C) do
    :publish
  end
  def message_type(:pub_ack) do
    0x0D
  end
  def message_type(0x0D) do
    :pub_ack
  end


  def return_code(0x00) do
    :ok
  end
  def return_code(0x01) do
    {:rejected, :congestion}
  end
  def return_code(0x02) do
    {:rejected, :invalid_topic_id}
  end
  def return_code(0x03) do
    {:rejected, :not_supported}
  end

end
