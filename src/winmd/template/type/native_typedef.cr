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

  def after_initialize
    @name = WinMD.fix_type_name(@name)
  end

  def fqdn
    fqdn_name = @name
    if @file.nil?
      if @file = WinMD.find_file_by_ns(@namespace)
        debug("ApiRef #{@name} had nil tfile but tfile is now set to #{@file.try &.namespace}")
      end
    end
    unless @file.try &.namespace == @namespace
      fqdn_name = @namespace + "::" + @name
    end
    fqdn_name
  end

  def render
    ECR.render "./src/winmd/ecr/native_typedef.ecr"
  end

  def file=(file : WinMD::File)
    super(file)
    @def_.file = file
  end
end