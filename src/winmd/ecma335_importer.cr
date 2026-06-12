require "ecma335"
require "set"

class WinMD::Ecma335Importer
  getter files : Array(WinMD::File)

  def initialize(@parsed : Ecma335::ParsedAssembly)
    @api = @parsed.api_model || raise "ECMA-335 parse did not produce api_model"
    @files = [] of WinMD::File
    @files_by_namespace = Hash(String, WinMD::File).new
    @converted_structs = Hash(String, WinMD::Type::Struct).new
    @converting_structs = Set(String).new
    @seen_import_names = Set(String).new
  end

  def import : Array(WinMD::File)
    build_types
    build_functions
    ensure_placeholder_types_for_missing_refs
    ensure_namespace_prefix_files
    @files.each(&.set_file)
    @files
  end

  private def build_types : Nil
    @api.types.each do |api_type|
      next if api_type.full_name == "<Module>"
      next if api_type.enclosing_type
      projected_namespace = projection_namespace(api_type.namespace_name)
      file = file_for_namespace(projected_namespace)
      if constants = convert_constants_container(api_type, projected_namespace)
        file.constants.concat(constants)
        next
      end
      if converted = convert_type(api_type, projected_namespace)
        file.types << converted
      end
    end
  end

  private def build_functions : Nil
    @api.types.each do |api_type|
      projected_namespace = projection_namespace(api_type.namespace_name)
      file = file_for_namespace(projected_namespace)
      api_type.methods.each do |method|
        next unless method.native_import
        next if @seen_import_names.includes?(method.native_import.not_nil!)
        function = build_function(method, projected_namespace)
        if function
          next if file.functions.any? { |existing| existing.name == function.name }
          file.functions << function
          @seen_import_names.add(function.name)
        end
      end
    end
  end

  private def file_for_namespace(namespace_name : String) : WinMD::File
    if file = @files_by_namespace[namespace_name]?
      return file
    end

    api_name = namespace_name.empty? ? "Global" : namespace_name
    file = WinMD::File.from_json("{}", "#{api_name}.json")
    @files_by_namespace[namespace_name] = file
    @files << file
    file
  end

  private def convert_type(api_type : Ecma335::ApiType, current_namespace : String) : WinMD::Type?
    if wrapper_typedef = convert_value_wrapper_typedef(api_type, current_namespace)
      return wrapper_typedef
    end

    if handle_typedef = convert_handle_typedef(api_type)
      return handle_typedef
    end

    if enum_type = convert_enum(api_type)
      return enum_type
    end

    if com_type = convert_com_interface(api_type, current_namespace)
      return com_type
    end

    if struct_type = convert_struct_or_union(api_type, current_namespace)
      return struct_type
    end

    nil
  end

  private def convert_com_interface(api_type : Ecma335::ApiType, current_namespace : String) : WinMD::Type::Com?
    return nil unless looks_like_com_interface?(api_type)

    methods = api_type.methods.map_with_index do |method, index|
      convert_com_method(method, current_namespace, index)
    end.compact
    return nil if methods.empty?

    base_interface = api_type.interfaces.first?
    interface_ref : JSON::Any
    if base_interface
      interface_ref = JSON.parse(parse_canonical_type(base_interface, current_namespace).to_json)
    else
      interface_ref = JSON::Any.new(nil)
    end

    method_json = methods.map { |method| JSON.parse(method.to_json) }
    from_json_type(
      "Com",
      {
        "Name"          => JSON::Any.new(api_type.name),
        "Architectures" => JSON::Any.new([] of JSON::Any),
        "Platform"      => JSON::Any.new(nil),
        "Guid"          => JSON::Any.new(extract_guid_attribute(api_type.custom_attributes)),
        "Methods"       => JSON::Any.new(method_json),
        "Interface"     => interface_ref,
      }
    ).as?(WinMD::Type::Com)
  end

  private def convert_com_method(method : Ecma335::ApiMethod, current_namespace : String, index : Int32) : WinMD::Method?
    signature = method.signature
    return_type_name = signature ? signature.canonical_return_type : "Void"
    return_type = convert_signature_to_type(return_type_name, current_namespace)

    params = method.params.map_with_index do |param, param_index|
      param_name = param.name.empty? ? "arg#{param_index + 1}" : param.name
      ptype = convert_signature_to_type(param.signature_type, current_namespace)
      JSON::Any.new({
        "Name" => JSON::Any.new(param_name),
        "Type" => JSON.parse(serialize_type(ptype)),
      })
    end

    method_name = method.name.empty? ? "method_#{index + 1}" : method.name
    method_json = {
      "Name"          => JSON::Any.new(method_name),
      "SetLastError"  => JSON::Any.new(false),
      "ReturnType"    => JSON.parse(serialize_type(return_type)),
      "ReturnAttrs"   => JSON::Any.new([] of JSON::Any),
      "Architectures" => JSON::Any.new([] of JSON::Any),
      "Platform"      => JSON::Any.new(nil),
      "Params"        => JSON::Any.new(params),
    }
    WinMD::Method.from_json(JSON::Any.new(method_json).to_json)
  end

  private def convert_constants_container(api_type : Ecma335::ApiType, current_namespace : String) : Array(WinMD::Constant)?
    return nil if api_type.fields.empty?
    is_apis_container = api_type.name == "Apis"
    return nil unless is_apis_container || api_type.methods.empty?
    return nil unless is_apis_container || api_type.fields.all? { |field| !field.constant_value.nil? }

    constants = [] of WinMD::Constant
    api_type.fields.each do |field|
      value = field.constant_value
      next unless value
      type_obj = convert_signature_to_type(field.signature, current_namespace)
      value_type = constant_value_type_for_signature(field.signature)
      value_any = constant_value_any(value)
      next unless value_any

      payload = {
        "Name"      => JSON::Any.new(field.name),
        "Type"      => JSON.parse(type_obj.to_json),
        "ValueType" => JSON::Any.new(value_type),
        "Value"     => value_any,
      }
      constants << WinMD::Constant.from_json(JSON::Any.new(payload).to_json)
    end

    return nil if constants.empty?
    constants
  end

  private def convert_value_wrapper_typedef(api_type : Ecma335::ApiType, current_namespace : String) : WinMD::Type::NativeTypedef?
    return nil unless api_type.methods.empty?
    return nil unless api_type.nested_types.empty?
    return nil unless api_type.fields.size == 1
    return nil unless api_type.name == api_type.name.upcase
    field = api_type.fields.first
    return nil unless field.name.downcase == "value"
    def_type = convert_signature_to_type(field.signature, current_namespace)

    from_json_type(
      "NativeTypedef",
      {
        "Name"               => JSON::Any.new(api_type.name),
        "Architectures"      => JSON::Any.new([] of JSON::Any),
        "Platform"           => JSON::Any.new(nil),
        "AlsoUsableFor"      => JSON::Any.new(nil),
        "Def"                => JSON.parse(def_type.to_json),
        "FreeFunc"           => JSON::Any.new(nil),
        "InvalidHandleValue" => JSON::Any.new(nil),
      }
    ).as?(WinMD::Type::NativeTypedef)
  end

  private def convert_handle_typedef(api_type : Ecma335::ApiType) : WinMD::Type::NativeTypedef?
    return nil unless !!(api_type.name =~ /^H[A-Z0-9_]+$/)

    from_json_type(
      "NativeTypedef",
      {
        "Name"               => JSON::Any.new(api_type.name),
        "Architectures"      => JSON::Any.new([] of JSON::Any),
        "Platform"           => JSON::Any.new(nil),
        "AlsoUsableFor"      => JSON::Any.new(nil),
        "Def"                => JSON.parse(pointer_to(native_type("Void")).to_json),
        "FreeFunc"           => JSON::Any.new(nil),
        "InvalidHandleValue" => JSON::Any.new(nil),
      }
    ).as?(WinMD::Type::NativeTypedef)
  end

  private def convert_enum(api_type : Ecma335::ApiType) : WinMD::Type::Enum?
    return nil unless looks_like_enum?(api_type)
    members = [] of JSON::Any
    api_type.fields.each do |field|
      next if field.name == "value__"
      next unless value = field.constant_value
      value_any = enum_value_any(value)
      next unless value_any
      members << JSON::Any.new({
        "Name"  => JSON::Any.new(field.name),
        "Value" => value_any,
      })
    end
    return nil if members.empty?

    integer_base = "Int32"
    if value_field = api_type.fields.find { |f| f.name == "value__" }
      if signature = value_field.signature
        integer_base = map_primitive_enum_base(canonicalize(signature))
      end
    end

    from_json_type(
      "Enum",
      {
        "Name"        => JSON::Any.new(api_type.name),
        "Architectures" => JSON::Any.new([] of JSON::Any),
        "Platform"    => JSON::Any.new(nil),
        "Flags"       => JSON::Any.new(false),
        "Scoped"      => JSON::Any.new(false),
        "Values"      => JSON::Any.new(members),
        "IntegerBase" => JSON::Any.new(integer_base),
      }
    ).as?(WinMD::Type::Enum)
  end

  private def convert_struct_or_union(api_type : Ecma335::ApiType, current_namespace : String) : WinMD::Type::Struct?
    return nil unless looks_like_structish?(api_type)
    if converted = @converted_structs[api_type.full_name]?
      return converted
    end
    return nil if @converting_structs.includes?(api_type.full_name)
    @converting_structs.add(api_type.full_name)

    fields = [] of JSON::Any
    api_type.fields.each do |field|
      next if field.name == "value__"
      field_type = convert_signature_to_type(field.signature, current_namespace)
      fields << JSON::Any.new({
        "Name" => JSON::Any.new(field.name),
        "Type" => JSON.parse(serialize_type(field_type)),
      })
    end

    kind = looks_like_union?(api_type) ? "Union" : "Struct"
    converted = from_json_type(
      kind,
      {
        "Name"          => JSON::Any.new(api_type.name),
        "Architectures" => JSON::Any.new([] of JSON::Any),
        "Platform"      => JSON::Any.new(nil),
        "Size"          => JSON::Any.new(0_i64),
        "PackingSize"   => JSON::Any.new(0_i64),
        "Fields"        => JSON::Any.new(fields),
        "NestedTypes"   => JSON::Any.new([] of JSON::Any),
        "Comment"       => JSON::Any.new(nil),
      }
    )
    struct_type = converted.as?(WinMD::Type::Struct)
    if struct_type
      @converted_structs[api_type.full_name] = struct_type
    end
    struct_type
  ensure
    @converting_structs.delete(api_type.full_name)
  end

  private def build_function(method : Ecma335::ApiMethod, current_namespace : String) : WinMD::Function?
    return nil unless import_name = method.native_import
    return nil unless valid_import_name?(import_name)
    signature = method.signature
    return_type_name = signature ? signature.canonical_return_type : "Void"
    return_type = convert_signature_to_type(return_type_name, current_namespace)

    params = method.params.map do |param|
      ptype = convert_signature_to_type(param.signature_type, current_namespace)
      JSON::Any.new({
        "Name"  => JSON::Any.new(param.name),
        "Type"  => JSON.parse(serialize_type(ptype)),
        "Attrs" => JSON::Any.new([] of JSON::Any),
      })
    end

    function_json = {
      "Name"          => JSON::Any.new(import_name),
      "SetLastError"  => JSON::Any.new(false),
      "DllImport"     => JSON::Any.new(method.native_module || "unknown"),
      "ReturnType"    => JSON.parse(serialize_type(return_type)),
      "ReturnAttrs"   => JSON::Any.new([] of JSON::Any),
      "Architectures" => JSON::Any.new([] of JSON::Any),
      "Platform"      => JSON::Any.new(nil),
      "Attrs"         => JSON::Any.new([] of JSON::Any),
      "Params"        => JSON::Any.new(params),
    }
    WinMD::Function.from_json(JSON::Any.new(function_json).to_json)
  end

  private def convert_signature_to_type(signature : String?, current_namespace : String) : WinMD::Type
    type_name = signature ? canonicalize(signature) : "Void"
    parse_canonical_type(type_name, current_namespace)
  end

  private def parse_canonical_type(type_name : String, current_namespace : String) : WinMD::Type
    value = type_name.strip
    return native_type("Void") if value.empty?

    if inner = extract_call_inner(value, "cmod_reqd")
      comma = inner.index(',')
      return parse_canonical_type(inner[(comma + 1)..].strip, current_namespace) if comma
    end

    if inner = extract_call_inner(value, "cmod_opt")
      comma = inner.index(',')
      return parse_canonical_type(inner[(comma + 1)..].strip, current_namespace) if comma
    end

    if inner = extract_call_inner(value, "array")
      child = parse_canonical_type(inner, current_namespace)
      return array_of(child)
    end

    if inner = extract_call_inner(value, "szarray")
      child = parse_canonical_type(inner, current_namespace)
      return array_of(child)
    end

    if extract_call_inner(value, "fnptr")
      return pointer_to(native_type("Void"))
    end

    if value.starts_with?("ref ")
      return pointer_to(parse_canonical_type(value[4..], current_namespace))
    end

    if value.ends_with?("*")
      return pointer_to(parse_canonical_type(value[0...-1], current_namespace))
    end

    if value.ends_with?("[]")
      child = parse_canonical_type(value[0...-2], current_namespace)
      return array_of(child)
    end

    if value.includes?('[') && value.ends_with?(']')
      base = value[0...value.index('[').not_nil!]
      child = parse_canonical_type(base, current_namespace)
      return array_of(child)
    end

    if primitive = map_primitive_type(value)
      return primitive
    end

    if value == "System.Object" || value == "typedref" || value == "string"
      return pointer_to(native_type("Void"))
    end

    if value.starts_with?("genericinst(") && value.ends_with?(")")
      return pointer_to(native_type("Void"))
    end

    if value.starts_with?("var(") || value.starts_with?("mvar(")
      return pointer_to(native_type("Void"))
    end

    if value.includes?('.')
      last_dot = value.rindex('.').not_nil!
      api = projection_namespace(value[0...last_dot])
      name = value[(last_dot + 1)..]
      ref = api_ref(name, api)
      return pointer_to(ref) if api_refers_to_com_interface?(api, name)
      return ref
    end

    default_api = current_namespace.empty? ? "Global" : current_namespace
    ref = api_ref(value, default_api)
    return pointer_to(ref) if api_refers_to_com_interface?(default_api, value)
    ref
  end

  private def projection_namespace(namespace_name : String) : String
    return "Global" if namespace_name.empty?

    if namespace_name.starts_with?("Windows.Win32")
      trimmed = namespace_name
      while trimmed.starts_with?("Windows.Win32")
        trimmed = trimmed.sub(/^Windows\.Win32\.?/, "")
      end
      return trimmed.empty? ? "Global" : trimmed
    end

    # Non-Win32 `Windows.*` namespaces come from WinRT metadata that we
    # don't actually parse — they show up as TypeRefs in signatures. Move
    # them under a `WinRT.` prefix so the projected modules (e.g.
    # `Win32cr::WinRT::Foundation::IPropertyValue`) clearly signal "this is
    # a placeholder for a foreign WinRT type" instead of colliding with the
    # real Win32 surface or hiding inside an opaque `Windows::` segment.
    if namespace_name.starts_with?("Windows.")
      return "WinRT." + namespace_name.sub(/^Windows\./, "")
    end

    namespace_name
  end

  private def ensure_namespace_prefix_files : Nil
    namespaces = @files_by_namespace.keys.reject(&.empty?)
    namespaces.each do |namespace|
      parts = namespace.split('.')
      next if parts.size <= 1
      (1...parts.size).each do |i|
        prefix = parts[0, i].join('.')
        next if @files_by_namespace.has_key?(prefix)
        file = WinMD::File.from_json("{}", "#{prefix}.json")
        @files_by_namespace[prefix] = file
        @files << file
      end
    end
  end

  private def ensure_placeholder_types_for_missing_refs : Nil
    refs = [] of {String, String}

    @files.each do |file|
      file.types.each do |type|
        collect_api_refs_from_type(type, refs)
      end
      file.functions.each do |function|
        collect_api_refs_from_type(function.return_type, refs)
        function.params.each { |param| collect_api_refs_from_type(param.type, refs) }
      end
    end

    refs.uniq.each do |api, name|
      next if name.empty?
      target_file = file_for_namespace(api)
      next if file_has_type_name?(target_file, name)
      placeholder = placeholder_type_for_missing_ref(name)
      target_file.types << placeholder if placeholder
    end
  end

  private def placeholder_type_for_missing_ref(name : String) : WinMD::Type?
    from_json_type(
      "NativeTypedef",
      {
        "Name"               => JSON::Any.new(name),
        "Architectures"      => JSON::Any.new([] of JSON::Any),
        "Platform"           => JSON::Any.new(nil),
        "AlsoUsableFor"      => JSON::Any.new(nil),
        "Def"                => JSON.parse(pointer_to(native_type("Void")).to_json),
        "FreeFunc"           => JSON::Any.new(nil),
        "InvalidHandleValue" => JSON::Any.new(nil),
      }
    )
  end

  private def file_has_type_name?(file : WinMD::File, name : String) : Bool
    file.types.any? do |type|
      type_name = extract_type_name(type)
      !type_name.nil? && type_name == name
    end
  end

  private def extract_type_name(type : WinMD::Type) : String?
    case type
    when WinMD::Type::Struct
      type.name
    when WinMD::Type::Union
      type.name
    when WinMD::Type::Enum
      type.name
    when WinMD::Type::Com
      type.name
    when WinMD::Type::Interface
      type.name
    when WinMD::Type::NativeTypedef
      type.name
    when WinMD::Type::FunctionPointer
      type.name
    when WinMD::Type::Native
      type.name
    when WinMD::Type::ApiRef
      type.name
    when WinMD::Type::MissingClrType
      type.name
    else
      nil
    end
  end

  private def collect_api_refs_from_type(type : WinMD::Type, refs : Array({String, String})) : Nil
    case type
    when WinMD::Type::ApiRef
      refs << {type.api, type.name}
    when WinMD::Type::PointerTo
      collect_api_refs_from_type(type.child, refs)
    when WinMD::Type::Array
      collect_api_refs_from_type(type.child, refs)
    when WinMD::Type::FunctionPointer
      collect_api_refs_from_type(type.return_type, refs)
      type.params.each { |param| collect_api_refs_from_type(param.type, refs) }
    when WinMD::Type::Struct
      type.fields.each { |field| collect_api_refs_from_type(field.type, refs) }
      type.nested_types.each { |nested| collect_api_refs_from_type(nested, refs) }
    when WinMD::Type::NativeTypedef
      collect_api_refs_from_type(type.def_, refs)
    when WinMD::Type::Com
      type.methods.each do |method|
        collect_api_refs_from_type(method.return_type, refs)
        method.params.each { |param| collect_api_refs_from_type(param.type, refs) }
      end
      if interface = type.interface
        collect_api_refs_from_type(interface, refs)
      end
    else
      # Native and other leaf kinds have no child refs.
    end
  end

  private def map_primitive_type(name : String) : WinMD::Type?
    canonical = name.downcase
    case canonical
    when "void" then native_type("Void")
    when "bool" then native_type("Bool")
    when "char" then native_type("UInt16")
    when "int8" then native_type("Int8")
    when "uint8" then native_type("UInt8")
    when "int16" then native_type("Int16")
    when "uint16" then native_type("UInt16")
    when "int32" then native_type("Int32")
    when "uint32" then native_type("UInt32")
    when "int64" then native_type("Int64")
    when "uint64" then native_type("UInt64")
    when "float32" then native_type("Float32")
    when "float64" then native_type("Float64")
    when "nint" then native_type("Int64")
    when "nuint" then native_type("UInt64")
    else
      nil
    end
  end

  private def map_primitive_enum_base(canonical_field_type : String) : String
    case canonical_field_type
    when "Int8", "UInt8", "Int16", "UInt16", "Int32", "UInt32", "Int64", "UInt64"
      canonical_field_type
    when "int8" then "Int8"
    when "uint8" then "UInt8"
    when "int16" then "Int16"
    when "uint16" then "UInt16"
    when "int32" then "Int32"
    when "uint32" then "UInt32"
    when "int64" then "Int64"
    when "uint64" then "UInt64"
    else
      "Int32"
    end
  end

  private def looks_like_enum?(api_type : Ecma335::ApiType) : Bool
    return false if api_type.fields.empty?
    return false unless api_type.fields.any? { |field| field.name == "value__" }
    api_type.fields.any? { |field| field.constant_value }
  end

  private def looks_like_structish?(api_type : Ecma335::ApiType) : Bool
    return false if looks_like_com_interface?(api_type)
    return false if looks_like_function_container?(api_type)
    return true if api_type.fields.any? { |field| field.name == "value__" } # enum (handled earlier)
    api_type.fields.any? || api_type.nested_types.any?
  end

  private def looks_like_function_container?(api_type : Ecma335::ApiType) : Bool
    return false if api_type.fields.any?
    api_type.methods.any? { |method| method.native_import }
  end

  private def looks_like_union?(api_type : Ecma335::ApiType) : Bool
    api_type.name.includes?("_Anonymous_e__Union") || api_type.name.ends_with?("Union")
  end

  private def looks_like_com_interface?(api_type : Ecma335::ApiType) : Bool
    return false if api_type.methods.empty?
    return false if api_type.fields.any?
    return false if api_type.methods.any? { |method| method.native_import }
    return true if api_type.name.starts_with?("I") && api_type.name.size > 1
    api_type.custom_attributes.any? { |attr| attr.includes?("GuidAttribute=") }
  end

  private def canonicalize(signature : String) : String
    Ecma335::SignatureCanonicalizer.new.canonicalize(signature)
  end

  private def native_type(name : String) : WinMD::Type
    from_json_type("Native", {"Name" => JSON::Any.new(name)})
  end

  private def pointer_to(child : WinMD::Type) : WinMD::Type
    from_json_type(
      "PointerTo",
      {"Child" => JSON.parse(serialize_type(child))}
    )
  end

  private def array_of(child : WinMD::Type) : WinMD::Type
    from_json_type(
      "Array",
      {
        "Shape" => JSON::Any.new({"Size" => JSON::Any.new(0_i64)}),
        "Child" => JSON.parse(serialize_type(child)),
      }
    )
  end

  private def api_ref(name : String, api : String) : WinMD::Type
    from_json_type(
      "ApiRef",
      {
        "Name"       => JSON::Any.new(name),
        "TargetKind" => JSON::Any.new("Default"),
        "Api"        => JSON::Any.new(api),
        "Parents"    => JSON::Any.new([] of JSON::Any),
      }
    )
  end

  private def from_json_type(kind : String, fields : Hash(String, JSON::Any)) : WinMD::Type
    payload = {"Kind" => JSON::Any.new(kind)}.merge(fields)
    WinMD::Type.from_json(JSON::Any.new(payload).to_json)
  end

  private def serialize_type(type : WinMD::Type) : String
    type.to_json
  end

  private def constant_value_type_for_signature(signature : String?) : String
    canonical = signature ? canonicalize(signature) : "Int32"
    case canonical
    when "Bool", "bool" then "Bool"
    when "UInt8", "uint8" then "UInt8"
    when "Int8", "int8" then "Int8"
    when "UInt16", "uint16" then "UInt16"
    when "Int16", "int16" then "Int16"
    when "UInt32", "uint32" then "UInt32"
    when "Int32", "int32" then "Int32"
    when "UInt64", "uint64" then "UInt64"
    when "Int64", "int64" then "Int64"
    when "Float32", "float32" then "Float32"
    when "Float64", "float64" then "Float64"
    when "string", "String" then "String"
    else
      "Int32"
    end
  end

  private def constant_value_any(raw : String) : JSON::Any?
    value = raw.strip
    return JSON::Any.new(true) if value == "true"
    return JSON::Any.new(false) if value == "false"

    if value.starts_with?("0x") || value.starts_with?("-0x")
      negative = value.starts_with?("-")
      hex = negative ? value[3..] : value[2..]
      parsed = hex.to_i64(16)
      parsed = -parsed if negative
      return JSON::Any.new(parsed)
    end

    return JSON::Any.new(value.to_i64) if value.matches?(/^-?\d+$/)
    return JSON::Any.new(value.to_f64) if value.matches?(/^-?\d+\.\d+$/)
    JSON::Any.new(value)
  rescue
    nil
  end

  private def enum_value_any(raw : String) : JSON::Any?
    value = raw.strip
    if value.starts_with?("0x") || value.starts_with?("-0x")
      negative = value.starts_with?("-")
      hex = negative ? value[3..] : value[2..]
      parsed = hex.to_i64(16)
      parsed = -parsed if negative
      return JSON::Any.new(parsed)
    end

    return JSON::Any.new(value.to_i64) if value.matches?(/^-?\d+$/)
    nil
  rescue
    nil
  end

  private def extract_call_inner(value : String, name : String) : String?
    prefix = "#{name}("
    return nil unless value.starts_with?(prefix)
    return nil unless value.ends_with?(")")
    value[prefix.size...-1]
  end

  private def valid_import_name?(name : String) : Bool
    !!(name =~ /^[A-Za-z_][A-Za-z0-9_]*$/)
  end

  private def extract_guid_attribute(custom_attributes : Array(String)) : String?
    custom_attributes.each do |attr|
      if match = attr.match(/GuidAttribute=([0-9a-fA-F\-]{36})/)
        return match[1]
      end
    end
    nil
  end

  private def api_refers_to_com_interface?(projected_api : String, type_name : String) : Bool
    full_namespace = projected_api_to_full_namespace(projected_api)
    return false if full_namespace.empty?
    full_name = "#{full_namespace}.#{type_name}"

    if api_type = @api.type?(full_name)
      return looks_like_com_interface?(api_type)
    end
    false
  end

  private def projected_api_to_full_namespace(projected_api : String) : String
    return "Windows.Win32" if projected_api == "Global"
    "Windows.Win32.#{projected_api}"
  end
end
