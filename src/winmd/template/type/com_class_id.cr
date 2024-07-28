class WinMD::Type::ComClassID < WinMD::Type
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  @name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "Guid")]
  property guid : String

  def hex_guid
    WinMD::Guid.new(@guid).to_hex_params
  end

  def name
    # Microsoft did not always adhere to a naming convention for their
    # clsid constants.
    if /^CLSID_/.match(@name)
      @name
    else
      "CLSID_" + @name
    end
  end

  def render
    ECR.render "./src/winmd/ecr/com_class_id.ecr"
  end
end