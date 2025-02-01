class WinMD::Type::Enum::EnumMember < WinMD::Base

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Value", converter: String::RawConverter)]
  property value : String

  @[JSON::Field(ignore: true)]
  property parent : WinMD::Type::Enum?

  @[JSON::Field(ignore: true)]
  property override_name : String = ""

  @[JSON::Field(ignore: true)]
  property override_value : String = ""

  def after_initialize
    @name = WinMD.fix_type_name(@name)
  end

  def render
    ECR.render "./src/winmd/ecr/enum_value.ecr"
  end

  def set_parent(tenum : Enum)
    @parent = tenum
  end

  def integer_base
    int_base = "i32"
    if parent = @parent
      parent_base = WinMD.rename_type(parent.integer_base)
      if /^Int/.match(parent_base)
        int_base = parent_base.gsub("Int", "i")
      elsif /^UInt/.match(parent_base)
        int_base = parent_base.gsub("UInt", "u")
      else
        raise Exception.new("Unknown integer base")
      end
    end
    int_base
  end

end