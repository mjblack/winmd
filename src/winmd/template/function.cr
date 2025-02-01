class WinMD::Function < WinMD::Base
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "SetLastError")]
  property set_last_error : Bool | Nil

  @[JSON::Field(key: "DllImport")]
  property dll_import : String

  @[JSON::Field(key: "ReturnType")]
  property return_type : WinMD::Type

  @[JSON::Field(key: "ReturnAttrs")]
  property return_attrs = [] of String

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "Params")]
  property params = [] of WinMD::Param

  @[JSON::Field(ignore: true)]
  getter libc_fun : Bool = false

  @[JSON::Field(ignore: true)]
  getter fun_alias : String = ""

  @[JSON::Field(ignore: true)]
  getter override_name : String = ""

  @[JSON::Field(ignore: true)]
  getter override_return_type : String = ""

  def after_initialize
    super
    if WinMD::Fun.exception?(@name)
      @libc_fun = true
    end
    @dll_import = @dll_import.downcase
    @fun_alias = @name.underscore
  end

  def apply_overrides
    Log.debug { "Checking for overrides for #{@name} in namespace #{@file.not_nil!.namespace}" }
    overrides = WinMD::FunOverride.find_overrides(@name, @file.not_nil!.namespace, WinMD::FunOverride::Type::Function)
    Log.debug { "Applying #{overrides.size} overrides for #{@name}" }
    apply_overrides(overrides)
  end

  def apply_overrides(overrides : Array(WinMD::FunOverride))
    overrides.each do |override|
      Log.trace { "Applying override rule type #{override.rule.type} for function #{@name}" }
      case override.rule.type
      when WinMD::FunOverride::Rule::Type::FunName
        Log.trace { "Applying name override for #{@name} -> #{override.rule.value}" }
        if override.rule.key == @name
          @name = override.rule.value
        end
      when WinMD::FunOverride::Rule::Type::FunAlias
        Log.trace { "Applying alias override for #{@name} -> #{override.rule.value}" }
        @fun_alias = override.rule.value
      when WinMD::FunOverride::Rule::Type::ParamName
        Log.trace { "Applying param name override for #{@name} -> #{override.rule.value}" }
        @params[override.rule.index].override_name = override.rule.value
      when WinMD::FunOverride::Rule::Type::ParamType
        Log.trace { "Applying param type override for #{@name} -> #{override.rule.value}" }
        @params[override.rule.index].override_type = override.rule.value
      when WinMD::FunOverride::Rule::Type::ReturnType
        Log.trace { "Applying return type override for #{@name} -> #{override.rule.value}" }
        @override_return_type = override.rule.value
      end
    end
  end

  def file=(file : WinMD::File)
    super(file)
    @return_type.file = file
    @params.each { |x| x.file = file }
  end

  def render
    ECR.render "./src/winmd/ecr/function.ecr"
  end

  def wrapper_render
    ECR.render "./src/winmd/ecr/function_wrapper.ecr"
  end
end