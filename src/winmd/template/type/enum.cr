class WinMD::Type::Enum < WinMD::Type

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Values")]
  property members = [] of WinMD::Type::Enum::EnumMember

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "Flags")]
  property flags : Bool

  @[JSON::Field(key: "Scoped")]
  property scoped : Bool

  @[JSON::Field(key: "IntegerBase")]
  @integer_base : String | Nil

  @[JSON::Field(ignore: true)]
  property override_name : String = ""

  def after_initialize
    @name = WinMD.fix_type_name(@name)
  end

  def render
    if @members.empty?
      ECR.render "./src/winmd/ecr/enum_empty.ecr"
    else
      ECR.render "./src/winmd/ecr/enum.ecr"
    end
  end

  def integer_base
    if int_base = @integer_base
      int_base = WinMD.rename_type(int_base)
      if WinMD::INT_TYPES.includes?(int_base)
        int_base
      else
        raise Exception.new("IntegerBase #{int_base} is unknown!")
      end
    else
      "Int32"
    end
  end

  def file=(file : File)
    super(file)
    @members.each { |enum_member| enum_member.file = file }
    @members.each { |enum_member| enum_member.set_parent(self) }
  end

  def apply_overrides
    overrides = WinMD::FunOverride.find_overrides(@name, @file.not_nil!.namespace, WinMD::FunOverride::Type::Enum)
    apply_overrides(overrides)
  end

  def apply_overrides(overrides : Array(WinMD::FunOverride))
    overrides.each do |override|
      case override.rule.type
      when WinMD::FunOverride::Rule::Type::EnumName
        Log.debug { "Applying name override for #{@name} -> #{override.rule.value}" }
        if override.rule.key == @name
          @override_name = override.rule.value
        end
      when WinMD::FunOverride::Rule::Type::EnumMemberName
        Log.debug { "Applying enum member name override for #{@name} -> #{override.rule.value}" }
        @members[override.rule.index].override_name = override.rule.value
      when WinMD::FunOverride::Rule::Type::EnumMemberValue
        Log.debug { "Applying enum member value override for #{@name} -> #{override.rule.value}" }
        @members[override.rule.index].override_value = override.rule.value
      end
    end
  end
end