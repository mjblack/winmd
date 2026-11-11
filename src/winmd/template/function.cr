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

  @[JSON::Field(key: "Params")]
  property params = [] of WinMD::Param

  @[JSON::Field(ignore: true)]
  getter libc_fun : Bool = false

  # LibC's declaration of this function when discovery found one; nil for
  # names that only come from fun_exceptions.json or --libc-funs.
  @[JSON::Field(ignore: true)]
  getter libc_signature : LibCFuns::Signature? = nil

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
      @libc_signature = WinMD::Fun.libc_signature?(@name)
    end
    @dll_import = normalize_dll_import(@dll_import)
    @fun_alias = @name.underscore
  end

  private def normalize_dll_import(value : String) : String
    normalized = value.downcase.strip
    normalized = normalized.sub(/\.dll$/, "")
    return "" if normalized.starts_with?("api-ms-")
    return "" if normalized.starts_with?("ext-ms-")
    normalized
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

  def wrapper_name : String
    (@override_name.empty? ? @name : @override_name).camelcase(lower: true)
  end

  def wrapper_return_type : String
    @override_return_type.empty? ? @return_type.render.to_s : @override_return_type
  end

  # True when the wrapper can forward to the stdlib's declaration instead of
  # being commented out: LibC's parameter list is known and has the same
  # arity as the metadata's.
  def libc_wrapper? : Bool
    signature = @libc_signature
    return false unless @libc_fun && signature
    params = signature.params
    !signature.varargs && !params.nil? && params.size == @params.size
  end

  # Body of a wrapper that forwards to Crystal's LibC. Each argument is
  # converted to the type LibC declares and the result back to this
  # wrapper's declared type, through the generated LibCBridge helpers.
  def libc_call : String
    signature = @libc_signature.not_nil!
    bridge = "#{WinMD.top_level_namespace}::LibCBridge"
    args = @params.zip(signature.params.not_nil!).map do |param, libc_param|
      name = param.override_name.empty? ? param.name : param.override_name
      "#{bridge}.arg(#{name}, #{libc_param.type})"
    end
    call = "::#{signature.lib_name}.#{signature.name}"
    call += "(#{args.join(", ")})" unless args.empty?
    return_type = wrapper_return_type
    return call if return_type == "Void"
    "#{bridge}.ret(#{call}, #{Function.value_type(return_type)})"
  end

  # `Foo*` is only valid where a type is expected; as a call argument it has
  # to be written `Pointer(Foo)`.
  def self.value_type(type : String) : String
    base = type.rstrip('*')
    (type.size - base.size).times { base = "Pointer(#{base})" }
    base
  end

  def render
    ECR.render "./src/winmd/ecr/function.ecr"
  end

  def wrapper_render
    ECR.render "./src/winmd/ecr/function_wrapper.ecr"
  end
end