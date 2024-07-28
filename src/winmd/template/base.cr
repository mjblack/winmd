@[JSON::Serializable::Options(presence: true, emit_nulls: true)]
abstract class WinMD::Base
  include JSON::Serializable
  include JSON::Serializable::Unmapped

  @[JSON::Field(ignore: true)]
  property file : WinMD::File?

  @[JSON::Field(ignore: true)]
  property pad_size : Int32 = 2

  @[JSON::Field(ignore: true)]
  property nested_type : Bool = false

  def after_initialize
  end

  def pad(p_size : Int32)
    str = ""
    p_size.times do
      str += " "
    end
    str
  end

  def pad
    pad(@pad_size)
  end

  def file=(file : WinMD::File)
    @file = file
  end
end