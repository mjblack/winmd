class WinMD::Type::Native < WinMD::Type

  @[JSON::Field(key: "Name")]
  property name : String

  def after_initialize
    @name = WinMD.rename_type(@name)
    super
  end

  def render
    ECR.render "./src/winmd/ecr/native.ecr"
  end
end