class WinMD::Type::FreeWidth < WinMD::Type

  @[JSON::Field(key: "Func")]
  property func : String

  def render
    ECR.render "./src/winmd/ecr/free_width.ecr"
  end
end