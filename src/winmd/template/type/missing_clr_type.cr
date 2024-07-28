# As far as I'm aware, the missing clr type will be Pointer(Void)
# because it is not in the metadata.
class WinMD::Type::MissingClrType < WinMD::Type

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Namespace")]
  property namespace : String

  def render
    ECR.render "./src/winmd/ecr/missing_clr_type.ecr"
  end
end