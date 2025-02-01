class WinMD::Type::Struct::StructField < WinMD::Base

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Type")]
  property type : WinMD::Type

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(ignore: true)]
  property override_name : String = ""

  @[JSON::Field(ignore: true)]
  property override_type : String = ""

  def after_initialize
    @name = WinMD.fix_param_name(@name)
    super
  end

  def file=(file : WinMD::File)
    super(file)
    @type.file = file
  end

  def render
    ECR.render "./src/winmd/ecr/struct_field.ecr"
  end
end