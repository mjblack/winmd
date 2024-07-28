class WinMD::Constant < WinMD::Base

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Type")]
  property type : WinMD::Type

  @[JSON::Field(key: "ValueType")]
  property valuetype : String

  @[JSON::Field(key: "Value", converter: String::RawConverter)]
  property value : String

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  def after_initialize
    @name = WinMD.fix_type_name(@name)
    case @valuetype
    when /Int/, /Float/
      t = @valuetype[0].downcase
      match = /[Int|Float](\d+)$/.match(@valuetype)
      if b = match
        bits = b[1]
        @value += "_#{t}#{bits}"
      else
        raise ArgumentError.new("Constant - after_initialize: Expected match data but got nil")
      end
    when /PropertyKey/
      dt = "UI::Shell::PropertiesSystem::PROPERTYKEY"
      d = JSON.parse(@value)
      guid = UUID.new(d["Fmtid"].as_s).unsafe_as(WinMD::Guid)
      pid = d["Pid"].as_i.to_u32
      @value = "#{dt}.new(LibC::GUID.new(#{guid.to_hex_params}), #{pid}_u32)"
    end
    super
  end

  def render
    ECR.render "./src/winmd/ecr/constant.ecr"
  end

end