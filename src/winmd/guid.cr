struct WinMD::Guid
  getter data1 : UInt32
  getter data2 : UInt16
  getter data3 : UInt16
  getter data4 : UInt8[8]

  def initialize(@data1 : UInt32, @data2 : UInt16, @data3 : UInt16, @data4 : UInt8[8])
  end

  def to_s
    sprintf("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x", @data1.byte_swap, @data2.byte_swap, @data3.byte_swap, @data4[0].byte_swap, @data4[1].byte_swap, @data4[2].byte_swap, @data4[3].byte_swap, @data4[4].byte_swap, @data4[5].byte_swap, @data4[6].byte_swap, @data4[7].byte_swap).downcase
  end

  def to_hex_params
    str = sprintf("0x%x_u32", @data1).to_s + ", "
    str += sprintf("0x%x_u16", @data2) + ", "
    str += sprintf("0x%x_u16", @data3) + ", "
    str += "StaticArray[" + @data4.map { |x| sprintf("0x%x_u8", x) }.join(", ") + "]"
    str
  end

  def self.new(str : String)
    guid = UUID.new(str)
    guid.unsafe_as(Guid)
  end
end