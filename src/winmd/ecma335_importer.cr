require "ecma335"

# Converts the `Ecma335::ApiModel` of a parsed `.winmd` into the win32json
# document shape that `WinMD::File` already consumes, one document per
# namespace. Keeping the JSON contract as the boundary means every template,
# override and alias mechanism of the JSON pipeline applies unchanged, and the
# intermediate documents can be dumped for diffing against real win32json.
class WinMD::Ecma335Importer
  WIN32_PREFIX = "Windows.Win32."

  # Windows.Win32.Foundation.Metadata.Architecture flag bits.
  ARCHITECTURES = {1 => "X86", 2 => "X64", 4 => "Arm64"}

  # ECMA-335 primitive element names to the .NET names win32json uses.
  PRIMITIVES = {
    "void"       => "Void",
    "bool"       => "Boolean",
    "char"       => "Char",
    "int8"       => "SByte",
    "uint8"      => "Byte",
    "int16"      => "Int16",
    "uint16"     => "UInt16",
    "int32"      => "Int32",
    "uint32"     => "UInt32",
    "int64"      => "Int64",
    "uint64"     => "UInt64",
    "float32"    => "Single",
    "float64"    => "Double",
    "nativeint"  => "IntPtr",
    "nativeuint" => "UIntPtr",
  }

  # Constant element types (from the Constant table) to win32json ValueType.
  CONSTANT_VALUE_TYPES = {
    "bool"    => "Boolean",
    "char"    => "Char",
    "int8"    => "SByte",
    "uint8"   => "Byte",
    "int16"   => "Int16",
    "uint16"  => "UInt16",
    "int32"   => "Int32",
    "uint32"  => "UInt32",
    "int64"   => "Int64",
    "uint64"  => "UInt64",
    "float32" => "Single",
    "float64" => "Double",
    "string"  => "String",
  }

  # Import modules that no user-mode program can link against: FORCEINLINE marks
  # header-only inline functions with no export anywhere, and ntdllk is the
  # kernel-mode ntdll. Emitting these would add unresolvable @[Link] libraries.
  UNLINKABLE_MODULES = {"forceinline", "ntdllk"}

  # Resolution context for type references inside a namespace: nested types
  # are referenced by bare name, so the enclosing chain must be known.
  record Context, namespace : String, parents : Array(String) = [] of String

  getter files : Array(WinMD::File)

  # When true, integer parameters and fields that carry an AssociatedEnum
  # attribute are typed as that enum, the way older metadata declared them.
  property? associated_enums : Bool = false

  def initialize(@parsed : Ecma335::ParsedAssembly)
    @api = @parsed.api_model || raise "ECMA-335 parse did not produce api_model"
    @files = [] of WinMD::File
    @enum_index = Hash(String, Array(Ecma335::ApiType)).new { |h, k| h[k] = [] of Ecma335::ApiType }
    @api.types.each { |t| @enum_index[t.name] << t if t.enum? }
  end

  # Namespaces that produce an output file, sorted. The namespace holding the
  # metadata attribute definitions themselves is not part of the API surface.
  def namespaces : Array(String)
    @api.types
      .map(&.namespace_name)
      .reject(&.empty?)
      .uniq
      .reject { |ns| ns == "#{WIN32_PREFIX}Foundation.Metadata" }
      .reject { |ns| @api.types_in_namespace(ns).all?(&.attribute_type?) }
      .sort
  end

  # win32json file/API name: the namespace without the Windows.Win32 prefix.
  def self.api_name(namespace : String) : String
    namespace.starts_with?(WIN32_PREFIX) ? namespace[WIN32_PREFIX.size..] : namespace
  end

  def import : Array(WinMD::File)
    namespaces.each do |ns|
      json = namespace_json(ns)
      @files << WinMD::File.from_json(json, "#{self.class.api_name(ns)}.json")
    end
    @files
  end

  # Writes one `<Api>.json` document per namespace into `dir`.
  def dump(dir : Path) : Nil
    Dir.mkdir_p(dir)
    namespaces.each do |ns|
      ::File.write(dir.join("#{self.class.api_name(ns)}.json"), namespace_json(ns, pretty: true))
    end
  end

  def namespace_json(namespace : String, pretty : Bool = false) : String
    types = @api.types_in_namespace(namespace)
    ctx = Context.new(namespace)
    containers = types.select(&.static_class?)

    JSON.build(indent: pretty ? "  " : nil) do |j|
      j.object do
        j.field "Constants" do
          j.array do
            containers.each { |t| t.fields.each { |f| emit_constant(j, f, ctx) } }
          end
        end
        j.field "Types" do
          j.array do
            types.each { |t| emit_type(j, t, ctx) }
          end
        end
        j.field "Functions" do
          j.array do
            containers.each do |t|
              t.methods.each do |m|
                next unless m.native_import
                if unlinkable?(m)
                  Log.debug { "Ecma335Importer: skipping #{m.name} (module #{m.native_module} cannot be linked)" }
                  next
                end
                emit_function(j, m, ctx)
              end
            end
          end
        end
        j.field "UnicodeAliases" do
          j.array do
            unicode_aliases(types).each { |name| j.string name }
          end
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Types
  # ------------------------------------------------------------------

  private def emit_type(j : JSON::Builder, t : Ecma335::ApiType, ctx : Context) : Nil
    return if t.static_class? || t.attribute_type? || t.name == "<Module>"

    if t.enum?
      emit_enum(j, t)
    elsif t.delegate?
      emit_function_pointer(j, t, ctx)
    elsif t.interface?
      emit_com(j, t, ctx)
    elsif t.value_type? && (t.has_attribute?("NativeTypedef") || t.has_attribute?("MetadataTypedef"))
      emit_native_typedef(j, t, ctx)
    elsif t.value_type? && t.fields.empty? && t.has_attribute?("Guid")
      # A COM coclass: an empty value type whose only payload is its CLSID.
      emit_com_class_id(j, t)
    elsif t.value_type?
      emit_struct(j, t, ctx)
    else
      Log.debug { "Ecma335Importer: skipping #{t.full_name} (base #{t.base_type}, flags 0x#{t.flags.to_s(16)})" }
    end
  end

  private def emit_common_header(j : JSON::Builder, t : Ecma335::ApiAttributed, name : String, kind : String) : Nil
    j.field "Name", name
    j.field "Architectures" { emit_architectures(j, t) }
    j.field "Platform", platform_of(t)
    j.field "Kind", kind
  end

  private def emit_enum(j : JSON::Builder, t : Ecma335::ApiType) : Nil
    integer_base = "Int32"
    if value_field = t.fields.find { |f| f.name == "value__" }
      if sig = value_field.signature
        integer_base = PRIMITIVES[sig]? || "Int32"
      end
    end

    j.object do
      emit_common_header(j, t, t.name, "Enum")
      j.field "Flags", t.has_attribute?("Flags")
      j.field "Scoped", t.has_attribute?("ScopedEnum")
      j.field "Values" do
        j.array do
          t.fields.each do |f|
            next if f.name == "value__"
            next unless value = f.constant_value
            j.object do
              j.field "Name", f.name
              j.field "Value" { j.raw(json_number(value)) }
            end
          end
        end
      end
      j.field "IntegerBase", integer_base
    end
  end

  private def emit_struct(j : JSON::Builder, t : Ecma335::ApiType, ctx : Context) : Nil
    inner = Context.new(ctx.namespace, ctx.parents + [t.name])
    j.object do
      emit_common_header(j, t, t.name, t.union? ? "Union" : "Struct")
      j.field "Size", t.class_size || 0
      j.field "PackingSize", t.packing_size || 0
      j.field "Fields" do
        j.array do
          t.fields.each do |f|
            j.object do
              j.field "Name", f.name
              j.field "Type" do
                if enum_type = associated_enum(f, f.signature, inner)
                  emit_api_ref(j, enum_type.name, "Default", self.class.api_name(enum_type.namespace_name), [] of String)
                else
                  emit_type_ref(j, f.signature, inner)
                end
              end
              j.field "Attrs" { j.array { attribute_names(f).each { |a| j.string a } } }
            end
          end
        end
      end
      j.field "NestedTypes" do
        j.array do
          t.nested_type_tokens.each do |token|
            nested = @api.type_by_token?(token)
            emit_struct(j, nested, inner) if nested
          end
        end
      end
      j.field "Comment", nil
    end
  end

  private def emit_native_typedef(j : JSON::Builder, t : Ecma335::ApiType, ctx : Context) : Nil
    invalid_handle = t.attribute?("InvalidHandleValue").try(&.fixed_arg?(0)).try(&.to_i64?)
    invalid_handle = nil if invalid_handle && !(Int32::MIN <= invalid_handle <= Int32::MAX)

    j.object do
      emit_common_header(j, t, t.name, "NativeTypedef")
      j.field "AlsoUsableFor", t.attribute?("AlsoUsableFor").try(&.fixed_arg?(0))
      j.field "Def" { emit_type_ref(j, t.fields.first?.try(&.signature), ctx) }
      j.field "FreeFunc", t.attribute?("RAIIFree").try(&.fixed_arg?(0))
      j.field "InvalidHandleValue", invalid_handle.try(&.to_i32)
    end
  end

  private def emit_function_pointer(j : JSON::Builder, t : Ecma335::ApiType, ctx : Context) : Nil
    invoke = t.methods.find { |m| m.name == "Invoke" }
    j.object do
      emit_common_header(j, t, t.name, "FunctionPointer")
      j.field "SetLastError", false
      j.field "ReturnType" { emit_type_ref(j, invoke.try(&.signature).try(&.return_type), ctx) }
      j.field "ReturnAttrs" { emit_return_attrs(j, invoke) }
      j.field "Attrs" { j.array { } }
      j.field "Params" { emit_params(j, invoke, ctx) }
    end
  end

  private def emit_com_class_id(j : JSON::Builder, t : Ecma335::ApiType) : Nil
    j.object do
      emit_common_header(j, t, t.name, "ComClassID")
      j.field "Guid", t.attribute?("Guid").try(&.value) || "00000000-0000-0000-0000-000000000000"
    end
  end

  private def emit_com(j : JSON::Builder, t : Ecma335::ApiType, ctx : Context) : Nil
    j.object do
      emit_common_header(j, t, t.name, "Com")
      j.field "Guid", t.attribute?("Guid").try(&.value)
      j.field "Attrs" { j.array { attribute_names(t).each { |a| j.string a } } }
      j.field "Interface" do
        if base = t.interfaces.first?
          emit_named_ref(j, base, ctx)
        else
          j.null
        end
      end
      j.field "Methods" do
        j.array do
          t.methods.each do |m|
            next if m.name == ".ctor"
            j.object do
              j.field "Name", m.name
              j.field "SetLastError", m.set_last_error?
              j.field "ReturnType" { emit_type_ref(j, m.signature.try(&.return_type), ctx) }
              j.field "ReturnAttrs" { emit_return_attrs(j, m) }
              j.field "Architectures" { emit_architectures(j, m) }
              j.field "Platform", platform_of(m)
              j.field "Attrs" { j.array { attribute_names(m).each { |a| j.string a } } }
              j.field "Params" { emit_params(j, m, ctx) }
            end
          end
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Functions and parameters
  # ------------------------------------------------------------------

  private def emit_function(j : JSON::Builder, m : Ecma335::ApiMethod, ctx : Context) : Nil
    j.object do
      j.field "Name", m.name
      j.field "SetLastError", m.set_last_error?
      j.field "DllImport", dll_import_name(m.native_module)
      j.field "ReturnType" { emit_type_ref(j, m.signature.try(&.return_type), ctx) }
      j.field "ReturnAttrs" { emit_return_attrs(j, m) }
      j.field "Architectures" { emit_architectures(j, m) }
      j.field "Platform", platform_of(m)
      j.field "Attrs" { j.array { attribute_names(m).each { |a| j.string a } } }
      j.field "Params" { emit_params(j, m, ctx) }
    end
  end

  private def emit_return_attrs(j : JSON::Builder, m : Ecma335::ApiMethod?) : Nil
    j.array do
      next unless m
      m.return_attributes.each do |attr|
        name = attr.name.rchop("Attribute")
        j.string name unless name.empty?
      end
    end
  end

  private def emit_params(j : JSON::Builder, m : Ecma335::ApiMethod?, ctx : Context) : Nil
    j.array do
      next unless m
      m.params.each do |p|
        j.object do
          j.field "Name", p.name
          j.field "Type" { emit_param_type(j, p, ctx) }
          j.field "Attrs" do
            j.array do
              j.string "In" if p.in?
              j.string "Out" if p.out?
              j.string "Optional" if p.optional?
              attribute_names(p).each { |a| j.string a }
            end
          end
        end
      end
    end
  end

  # A pointer parameter carrying NativeArrayInfo becomes an LPArray.
  private def emit_param_type(j : JSON::Builder, p : Ecma335::ApiParam, ctx : Context) : Nil
    sig = p.signature_type
    if (enum_type = associated_enum(p, sig, ctx))
      emit_api_ref(j, enum_type.name, "Default", self.class.api_name(enum_type.namespace_name), [] of String)
    elsif sig && (info = p.attribute?("NativeArrayInfo")) && (head_inner = split_signature(sig)) && head_inner[0] == "ptr"
      j.object do
        j.field "Kind", "LPArray"
        j.field "NullNullTerm", p.has_attribute?("NullNullTerminated")
        j.field "CountConst", info.named_arg?("CountConst").try(&.to_i64?) || -1
        j.field "CountParamIndex", info.named_arg?("CountParamIndex").try(&.to_i64?) || -1
        j.field "Child" { emit_type_ref(j, head_inner[1], ctx) }
      end
    else
      emit_type_ref(j, sig, ctx)
    end
  end

  # ------------------------------------------------------------------
  # Constants
  # ------------------------------------------------------------------

  private def emit_constant(j : JSON::Builder, f : Ecma335::ApiField, ctx : Context) : Nil
    if f.literal? && (value = f.constant_value) && (ct = f.constant_type) && (value_type = CONSTANT_VALUE_TYPES[ct]?)
      # HKEY_LOCAL_MACHINE, INVALID_HANDLE_VALUE, HWND_BROADCAST, MSIDBOPEN_*:
      # integers cast to a pointer typedef in the headers. Keep them pointers.
      if (sig = f.signature) && pointer_typedef?(sig) && (address = pointer_address(value))
        j.object do
          j.field "Name", f.name
          j.field "Type" { emit_type_ref(j, sig, ctx) }
          j.field "ValueType", "Pointer"
          j.field "Value" { j.raw(address.to_s) }
          j.field "Attrs" { j.array { attribute_names(f).each { |a| j.string a } } }
        end
        return
      end

      literal = constant_literal(ct, value)
      return unless literal
      j.object do
        j.field "Name", f.name
        j.field "Type" { emit_type_ref(j, f.signature, ctx) }
        j.field "ValueType", value_type
        j.field "Value" { j.raw(literal) }
        j.field "Attrs" { j.array { attribute_names(f).each { |a| j.string a } } }
      end
    elsif guid = f.attribute?("Guid").try(&.value)
      j.object do
        j.field "Name", f.name
        j.field "Type" { emit_native(j, "Guid") }
        j.field "ValueType", "Guid"
        j.field "Value", guid
        j.field "Attrs" { j.array { } }
      end
    elsif (sig = f.signature) && (constant = f.attribute?("ConstantAttribute")) && (key = property_key(constant))
      value_type = sig.includes?("DEVPROPKEY") ? "DevPropKey" : (sig.includes?("PROPERTYKEY") ? "PropertyKey" : nil)
      return unless value_type
      j.object do
        j.field "Name", f.name
        j.field "Type" { emit_type_ref(j, sig, ctx) }
        j.field "ValueType", value_type
        j.field "Value" do
          j.object do
            j.field "Fmtid", key[0]
            j.field "Pid", key[1]
          end
        end
        j.field "Attrs" { j.array { } }
      end
    else
      Log.debug { "Ecma335Importer: skipping constant #{f.name} (#{f.signature})" }
    end
  end

  # True for native typedefs whose underlying field is a pointer
  # (HANDLE, HKEY, HWND, PWSTR, ...).
  private def pointer_typedef?(signature : String) : Bool
    return false unless signature.starts_with?("valuetype(") && signature.ends_with?(')')
    target = @api.type?(signature[10...-1]) || return false
    return false unless target.has_attribute?("NativeTypedef") || target.has_attribute?("MetadataTypedef")
    target.fields.first?.try(&.signature).try(&.starts_with?("ptr(")) || false
  end

  # The address an integer constant denotes once cast to a pointer: signed
  # values sign-extend to 64 bits, as `(HKEY)(ULONG_PTR)(LONG)0x80000002` does.
  private def pointer_address(value : String) : UInt64?
    if signed = value.to_i64?
      signed.to_u64!
    else
      value.to_u64?
    end
  end

  # Raw JSON token for a decoded Constant-table value, or nil when it cannot
  # be represented (non-finite floats).
  private def constant_literal(constant_type : String, value : String) : String?
    case constant_type
    when "string"
      value.to_json
    when "bool"
      value == "true" ? "true" : "false"
    when "char"
      (value.empty? ? 0 : value[0].ord).to_s
    when "float32", "float64"
      return nil if value.includes?("Infinity") || value.includes?("NaN")
      value.includes?('.') || value.includes?('e') ? value : "#{value}.0"
    else
      json_number(value)
    end
  end

  # "{a, b, c, d0, ..., d7}, pid" from ConstantAttribute -> {guid, pid}
  private def property_key(attr : Ecma335::ApiAttribute) : {String, Int64}?
    text = attr.fixed_arg?(0)
    return nil unless text
    match = /\{([^}]*)\},\s*(\d+)/.match(text)
    return nil unless match
    parts = match[1].split(',').map(&.strip.to_u64?)
    return nil if parts.size != 11 || parts.any?(&.nil?)
    nums = parts.map(&.not_nil!)
    guid = sprintf("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
      nums[0], nums[1], nums[2], nums[3], nums[4], nums[5], nums[6], nums[7], nums[8], nums[9], nums[10])
    {guid, match[2].to_i64}
  end

  # ------------------------------------------------------------------
  # Type references
  # ------------------------------------------------------------------

  # Emits a win32json "Type" object for a raw signature-decoder type string
  # such as `ptr(valuetype(Windows.Win32.Foundation.RECT))`.
  private def emit_type_ref(j : JSON::Builder, signature : String?, ctx : Context) : Nil
    sig = signature.try(&.strip) || "void"

    if primitive = PRIMITIVES[sig]?
      return emit_native(j, primitive)
    end

    case sig
    when "string", "object", "typedbyref"
      return emit_pointer(j) { emit_native(j, "Void") }
    end

    parts = split_signature(sig)
    unless parts
      Log.debug { "Ecma335Importer: unknown type signature #{sig}" }
      return emit_pointer(j) { emit_native(j, "Void") }
    end
    head, inner, tail = parts

    case head
    when "ptr", "byref"
      emit_pointer(j) { emit_type_ref(j, inner, ctx) }
    when "szarray"
      emit_array(j, nil) { emit_type_ref(j, inner, ctx) }
    when "array"
      size = tail.match(/\A\[(\d+)\]\z/).try { |m| m[1].to_i }
      emit_array(j, size) { emit_type_ref(j, inner, ctx) }
    when "valuetype", "class"
      emit_named_ref(j, inner, ctx)
    else
      Log.debug { "Ecma335Importer: unsupported type signature #{sig}" }
      emit_pointer(j) { emit_native(j, "Void") }
    end
  end

  # `Windows.Win32.Foundation.RECT` -> ApiRef; bare names are nested types of
  # the current struct chain; anything outside Windows.Win32 is opaque.
  private def emit_named_ref(j : JSON::Builder, full_name : String, ctx : Context) : Nil
    if full_name == "System.Guid"
      return emit_native(j, "Guid")
    end

    unless full_name.starts_with?(WIN32_PREFIX)
      if full_name.includes?('.')
        return emit_pointer(j) { emit_native(j, "Void") }
      end
      # Nested type, referenced by bare name from inside its enclosing struct.
      return emit_api_ref(j, full_name, "Default", self.class.api_name(ctx.namespace), ctx.parents)
    end

    target = @api.type?(full_name)
    last_dot = full_name.rindex('.').not_nil!
    namespace = full_name[0...last_dot]
    name = full_name[(last_dot + 1)..]

    unless target
      j.object do
        j.field "Kind", "MissingClrType"
        j.field "Name", name
        j.field "Namespace", self.class.api_name(namespace)
      end
      return
    end

    kind = if target.interface?
             "Com"
           elsif target.delegate?
             "FunctionPointer"
           else
             "Default"
           end
    emit_api_ref(j, name, kind, self.class.api_name(namespace), [] of String)
  end

  private def emit_api_ref(j : JSON::Builder, name : String, target_kind : String, api : String, parents : Array(String)) : Nil
    j.object do
      j.field "Kind", "ApiRef"
      j.field "Name", name
      j.field "TargetKind", target_kind
      j.field "Api", api
      j.field "Parents" { j.array { parents.each { |p| j.string p } } }
    end
  end

  private def emit_native(j : JSON::Builder, name : String) : Nil
    j.object do
      j.field "Kind", "Native"
      j.field "Name", name
    end
  end

  private def emit_pointer(j : JSON::Builder, &) : Nil
    j.object do
      j.field "Kind", "PointerTo"
      j.field "Child" { yield }
    end
  end

  private def emit_array(j : JSON::Builder, size : Int32?, &) : Nil
    j.object do
      j.field "Kind", "Array"
      j.field "Shape" do
        if size
          j.object { j.field "Size", size }
        else
          j.null
        end
      end
      j.field "Child" { yield }
    end
  end

  # `head(inner)tail` -> {head, inner, tail}; nil when not of that shape.
  private def split_signature(sig : String) : {String, String, String}?
    open = sig.index('(')
    return nil unless open
    head = sig[0...open]
    depth = 0
    close = nil
    (open...sig.size).each do |i|
      case sig[i]
      when '(' then depth += 1
      when ')'
        depth -= 1
        if depth == 0
          close = i
          break
        end
      end
    end
    return nil unless close
    {head, sig[(open + 1)...close], sig[(close + 1)..]}
  end

  # ------------------------------------------------------------------
  # Attributes, architectures, misc
  # ------------------------------------------------------------------

  private def emit_architectures(j : JSON::Builder, t : Ecma335::ApiAttributed) : Nil
    j.array do
      architectures_of(t).each { |a| j.string a }
    end
  end

  private def architectures_of(t : Ecma335::ApiAttributed) : Array(String)
    bits = 0
    t.attributes("SupportedArchitecture").each do |attr|
      bits |= attr.fixed_arg?(0).try(&.to_i?) || 0
    end
    ARCHITECTURES.compact_map { |bit, name| (bits & bit) != 0 ? name : nil }
  end

  private def platform_of(t : Ecma335::ApiAttributed) : String?
    t.attribute?("SupportedOSPlatform").try(&.fixed_arg?(0))
  end

  # Attribute short names without the "Attribute" suffix, e.g. "Const",
  # matching the win32json "Attrs" lists. Bookkeeping attributes are omitted.
  private def attribute_names(t : Ecma335::ApiAttributed) : Array(String)
    t.custom_attributes.compact_map do |attr|
      name = attr.name.rchop("Attribute")
      case name
      when "Documentation", "SupportedOSPlatform", "SupportedArchitecture", "Guid",
           "NativeArrayInfo", "MemorySize", "NativeTypedef", "MetadataTypedef",
           "RAIIFree", "InvalidHandleValue", "AlsoUsableFor", "Flags", "ScopedEnum",
           "UnmanagedFunctionPointer", "StructSizeField", "NativeBitfield", "NativeEncoding"
        nil
      else
        name
      end
    end
  end

  # The enum named by an AssociatedEnum attribute on an integer-typed member,
  # preferring one in the current namespace. Only active with
  # `associated_enums?`.
  private def associated_enum(t : Ecma335::ApiAttributed, signature : String?, ctx : Context) : Ecma335::ApiType?
    return nil unless associated_enums?
    return nil unless signature && PRIMITIVES.has_key?(signature)
    name = t.attribute?("AssociatedEnum").try(&.fixed_arg?(0))
    return nil unless name
    candidates = @enum_index[name]? || return nil
    candidates.find { |e| e.namespace_name == ctx.namespace } || candidates.first?
  end

  private def unlinkable?(m : Ecma335::ApiMethod) : Bool
    UNLINKABLE_MODULES.includes?(dll_import_name(m.native_module).downcase)
  end

  private def dll_import_name(native_module : String?) : String
    name = native_module || "unknown"
    name.sub(/\.dll\z/i, "")
  end

  # Names for which both an A and a W variant exist in this namespace.
  private def unicode_aliases(types : Array(Ecma335::ApiType)) : Array(String)
    names = Set(String).new
    types.each do |t|
      names << t.name
      if t.static_class?
        t.methods.each { |m| names << m.name if m.native_import }
      end
    end
    names.compact_map do |name|
      next nil unless name.ends_with?('A') && name.size > 1
      base = name.rchop
      names.includes?("#{base}W") ? base : nil
    end.sort
  end

  # Integer constant text as a raw JSON token; anything else becomes a string.
  private def json_number(value : String) : String
    value =~ /\A-?\d+\z/ ? value : value.to_json
  end
end
