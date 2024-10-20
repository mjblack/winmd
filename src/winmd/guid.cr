struct WinMD::Guid
  getter data1 : UInt32
  getter data2 : UInt16
  getter data3 : UInt16
  getter data4 : UInt8[8]

  def initialize(str : String)
    if /[\{\}]/.match(str)
      str = str.gsub(/[\{\}]/,"")
    end
    uuid = UUID.new(str, version: UUID::Version::V4, variant: UUID::Variant::Microsoft)
    guid = uuid.unsafe_as(Guid)
    @data1 = guid.data1
    @data2 = guid.data2
    @data3 = guid.data3
    @data4 = guid.data4
  end

  def initialize(@data1 : UInt32, @data2 : UInt16, @data3 : UInt16, @data4 : UInt8[8])
  end

  def to_s
    sprintf("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x", @data1.byte_swap, @data2.byte_swap, @data3.byte_swap, @data4[0].byte_swap, @data4[1].byte_swap, @data4[2].byte_swap, @data4[3].byte_swap, @data4[4].byte_swap, @data4[5].byte_swap, @data4[6].byte_swap, @data4[7].byte_swap).downcase
    #sprintf("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x", @data1, @data2, @data3, @data4[0], @data4[1], @data4[2], @data4[3], @data4[4], @data4[5], @data4[6], @data4[7]).downcase
  end

  def to_hex_params
    str = sprintf("0x%x_u32", @data1.byte_swap).to_s + ", "
    str += sprintf("0x%x_u16", @data2.byte_swap) + ", "
    str += sprintf("0x%x_u16", @data3.byte_swap) + ", "
    str += "StaticArray[" + @data4.map { |x| sprintf("0x%x_u8", x.byte_swap) }.join(", ") + "]"
    str
  end

  def self.new(str : String)
    guid = UUID.new(str)
    guid.unsafe_as(Guid)
  end
end