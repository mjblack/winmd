class WinMD::Type::NativeTypedef < WinMD::Type
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "AlsoUsableFor")]
  property also_usable_for : String | Nil

  @[JSON::Field(key: "Def")]
  property def_ : WinMD::Type

  @[JSON::Field(key: "FreeFunc")]
  property free_func : String | Nil

  @[JSON::Field(key: "InvalidHandleValue")]
  property invalid_handle_value : Int32 | Nil

  @[JSON::Field(ignore: true)]
  property override : String?

  def after_initialize
    @name = WinMD.fix_type_name(@name)
    if WinMD.has_alias?(@name)
      @override = WinMD.get_alias(@name)
    end
  end

  def fqdn
    fqdn_name = @name
    unless @file.try &.namespace == @namespace
      fqdn_name = @namespace + "::" + @name
    end
    fqdn_name
  end

  def render
    data_type = @override ? @override.not_nil! : @def_.render
    ECR.render "./src/winmd/ecr/native_typedef.ecr"
  end

  def file=(file : WinMD::File)
    super(file)
    @def_.file = file
  end
end
