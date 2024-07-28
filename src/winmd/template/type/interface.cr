class WinMD::Type::Interface < WinMD::Type

  @[JSON::Field(key: "Name")]
  property name : String

  def render
    ECR.render "./src/winmd/ecr/interface.ecr"
  end
end