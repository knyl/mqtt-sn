defmodule Mqttsn do

  def protocol_id() do
    0x01
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
