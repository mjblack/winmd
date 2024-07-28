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
    kinds_list = ["TFunction"] of String
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

  def has_type?(str_type : String)
    if @types.find { |x| x.name == str_type } ||
       @functions.find { |x| x.name == str_type } ||
       @constants.find { |x| x.name == str_type }
      true
    else
      false
    end
  end



  def self.from_json(json_data, filename)
    file = from_json(json_data)
    file.file_path = filename
    file.set_file
    file
  end
end