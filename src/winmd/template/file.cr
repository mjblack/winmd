class WinMD::File < WinMD::Base

  @[JSON::Field(key: "Constants")]
  property constants = [] of Constant

  @[JSON::Field(key: "Types")]
  property types = [] of WinMD::Type

  @[JSON::Field(key: "Functions")]
  property functions = [] of Function

  @[JSON::Field(key: "UnicodeAliases")]
  property unicode_aliases = [] of String

  @[JSON::Field(ignore: true)]
  property file_name : String = ""

  @[JSON::Field(ignore: true)]
  property file_path : String = ""

  @[JSON::Field(ignore: true)]
  property orig_file_name : String = ""

  @[JSON::Field(ignore: true)]
  property namespace : String = ""

  @[JSON::Field(ignore: true)]
  property api : String = ""

  @[JSON::Field(ignore: true)]
  property links = [] of String

  @[JSON::Field(ignore: true)]
  getter rel_path : String = ""

  @[JSON::Field(ignore: true)]
  getter includes = [] of WinMD::Include

  def set_file
    @constants.each do |c|
      c.file = self
    end
    @types.each do |t|
      t.file = self
    end
    @functions.each do |f|
      f.file = self
    end
    @includes.each do |i|
      i.resolve_path
    end
  end

  def ==(other : WinMD::File) : Bool
    qualified_path == other.qualified_path
  end

  def enums
    @types.select(WinMD::Type::Enum)
  end

  def native_typedefs
    @types.select(WinMD::Type::NativeTypedef)
  end

  def com_interfaces
    @types.select(WinMD::Type::Com).map { |x| x.as(WinMD::Type::Com) }
  end

  def structs_and_unions
    @types.select(WinMD::Type::Struct).map { |x| x }
  end

  def find_com_interface(name : String)
    com_interfaces.find { |x| x.name == name }
  end

  def render
    @functions.each do |f|
      next if f.dll_import.empty?
      if WinMD.dll_exception?(f.dll_import)
        next
      end
      unless @links.includes?(f.dll_import)
        @links << f.dll_import
      end
    end
    @types.each do |t|
      if t.is_a?(WinMD::Type::Struct)
        t.namespace = @namespace
      end
    end
    file_render = ECR.render("./src/winmd/ecr/file.ecr").split("\n")
    while file_render[0].empty?
      file_render.shift
    end
    file_render.join("\n")
  end

  def file_path=(filename : String)
    @orig_file_name = ::File.basename(filename, ".json")
    @api = filename.gsub(".json", "")
    _filename = @orig_file_name.underscore.gsub(".", "/")
    _dir = ::File.dirname(_filename)
    @file_path = "src/" + WinMD.top_level_namespace.downcase 
    if _dir == "."
      @rel_path = ""
    else
      @file_path += "/" + _dir
      @rel_path = _dir
    end
    @file_name = ::File.basename(_filename) + ".cr"
    @namespace = WinMD.top_level_namespace + "::" + @orig_file_name.gsub(".", "::")
  end

  def qualified_path
    Path.new(@file_path).join(@file_name)
  end

  # Add includes but only if its unique
  def add_include(inc : WinMD::Include)
    unless @includes.includes?(inc) || inc.same_file
      @includes << inc
      @includes.compact!
    end
  end

  def get_includes
    @includes.each { |x| x.resolve_path }
    includes_map = @includes.reject do |x|
      x.same_file
    end
    includes_map
  end

  def get_kinds
    kinds_list = [] of String
    @types.each do |type|
      kind = type.class.to_s
      unless kinds_list.includes?(kind)
        kinds_list << kind
      end
    end
    kinds_list
  end

  def get_types
    types_list = [] of WinMD::Base
    types_list += @constants.sort { |a,b| b.name <=> a.name }

    # Hopefully it will be sorted by type then name.
    types_list += @types.sort { |a,b| b.name <=> a.name }.sort { |a, b| b.class.to_s <=> a.class.to_s }
    types_list += @functions.sort { |a,b| b.name <=> a.name }
    types_list
  end

  def has_kind?(str_kind : String)
    get_kinds.includes?(str_kind)
  end

  # True if this file would render as a bare `module ... extend self end`
  # with no constants, types, functions, or unicode aliases.
  # Produced by `ensure_namespace_prefix_files` when a namespace appears only
  # as an intermediate prefix and never contributes real content.
  def empty_shell?
    @constants.empty? &&
      @types.empty? &&
      @functions.empty? &&
      @unicode_aliases.empty?
  end

  # True if this file lives outside the projected Win32 namespace tree —
  # i.e. it was created for a `Windows.Foundation.*`, `Windows.Storage.*`,
  # etc. WinRT type that was referenced from a Win32 type via ApiRef but
  # has no metadata in `Windows.Win32.winmd`. The importer remaps these
  # to a `WinRT.*` namespace, so the prefix check here matches the
  # projected form, not the raw CLR namespace.
  def foreign?
    @orig_file_name.starts_with?("WinRT.")
  end

  # True if the file contains only placeholder NativeTypedef -> Void*
  # entries (no real constants, functions, or richer types). These are
  # emitted by `Ecma335Importer#ensure_placeholder_types_for_missing_refs`
  # to keep ApiRefs resolvable.
  def placeholder_only?
    return false unless @constants.empty?
    return false unless @functions.empty?
    return false unless @unicode_aliases.empty?
    return false if @types.empty?
    @types.all? { |t| placeholder_typedef?(t) }
  end

  private def placeholder_typedef?(type : WinMD::Type) : Bool
    return false unless type.is_a?(WinMD::Type::NativeTypedef)
    def_ = type.as(WinMD::Type::NativeTypedef).def_
    return false unless def_.is_a?(WinMD::Type::PointerTo)
    child = def_.as(WinMD::Type::PointerTo).child
    child.is_a?(WinMD::Type::Native) &&
      child.as(WinMD::Type::Native).name == "Void"
  end

  def has_type?(str_type : String)
    if @types.find { |x| x.name == str_type } ||
       @functions.find { |x| x.name == str_type } ||
       @constants.find { |x| x.name == str_type }
      true
    else
      false
    end
  end

  def process_overrides
    Log.debug { "{File}Applying overrides for #{@namespace} - #{@file_name}" }
    @functions.each(&.apply_overrides)
    structs_and_unions.each(&.apply_overrides)
    enums.each(&.apply_overrides)
  end

  def self.from_json(json_data, filename)
    file = from_json(json_data)
    file.file_path = filename
    file.set_file
    file
  end
end