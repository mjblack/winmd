class WinMD::Type::FunctionPointer < WinMD::Type
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "SetLastError")]
  property set_last_error : Bool | Nil

  @[JSON::Field(key: "ReturnType")]
  property return_type : Type

  @[JSON::Field(key: "ReturnAttrs")]
  property return_attrs = [] of String

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "Params")]
  property params = [] of WinMD::Param

  def render
    ECR.render "./src/winmd/ecr/function_pointer.ecr"
  end

  def file=(file : WinMD::File)
    super(file)
    @params.each { |x| x.file = file }
    @return_type.file = file
  end

  def after_initialize
    super
    @name = WinMD.fix_type_name(@name)
  end
end