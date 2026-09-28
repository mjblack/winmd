class WinMD::Constant < WinMD::Base

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Type")]
  property type : WinMD::Type

  @[JSON::Field(key: "ValueType")]
  property valuetype : String

  @[JSON::Field(key: "Value", converter: String::RawConverter)]
  property value : String

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
      @value = key_value("UI::Shell::PropertiesSystem::PROPERTYKEY")
    when /DevPropKey/
      @value = key_value("Devices::Properties::DEVPROPKEY")
    when /Guid/
      guid = WinMD::Guid.new(JSON.parse(@value).as_s)
      @value = "LibC::GUID.new(#{guid.to_hex_params})"
    end
    super
  end

  # PROPERTYKEY / DEVPROPKEY style constants: {"Fmtid": guid, "Pid": n}.
  # The struct type comes from the constant's own type reference when it is
  # an ApiRef, so the constant follows the struct if metadata moves it.
  private def key_value(fallback_type : String) : String
    dt = fallback_type
    if ref = @type.as?(WinMD::Type::ApiRef)
      dt = WinMD.fix_namespace(ref.api)[0] + "::" + ref.name
    end
    d = JSON.parse(@value)
    guid = UUID.new(d["Fmtid"].as_s).unsafe_as(WinMD::Guid)
    pid = d["Pid"].as_i.to_u32
    "#{dt}.new(LibC::GUID.new(#{guid.to_hex_params}), #{pid}_u32)"
  end

  def file=(file : WinMD::File)
    super(file)
    @type.file = file
  end

  def render
    ECR.render "./src/winmd/ecr/constant.ecr"
  end

end
