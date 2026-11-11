require "log"
require "json"
require "yaml"
require "ecr"
require "big"
require "uuid"
require "file_utils"
require "compiler/crystal/syntax"

require "admiral"
require "git-repository"
require "ecma335"

require "./winmd/fun_override"
require "./winmd/fun_param"
require "./winmd/libc_funs"
require "./winmd/fun"
require "./winmd/architecture"
require "./winmd/template/base"
require "./winmd/template/file"
require "./winmd/template/constant"
require "./winmd/template/type"
require "./winmd/template/param"
require "./winmd/template/function"
require "./winmd/template/method"
require "./winmd/template/include"
require "./winmd/template/unicode_alias"
require "./winmd/guid"
require "./winmd/ecma335_importer"

module WinMD
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  INT_TYPES = {{Int.subclasses.map { |x| x.stringify }}}

  class_property files = [] of File
  class_property crystal_keywords = [] of String
  @@dll_exceptions = [] of String
  @@data_type_aliases = {} of String => String

  # Built-in mapping from the .NET-style names used by win32json (and by the
  # winmd importer) to Crystal types. `data_type_aliases.json` in the working
  # directory adds to or overrides these, so a generator run without any
  # override files still renders every file.
  DEFAULT_TYPE_ALIASES = {
    "Char"    => "UInt16",
    "Single"  => "Float32",
    "Double"  => "Float64",
    "SByte"   => "Int8",
    "Byte"    => "UInt8",
    "Guid"    => "LibC::GUID",
    "UIntPtr" => "LibC::UIntPtrT",
    "IntPtr"  => "LibC::IntPtrT",
    "Boolean" => "Bool",
    "HANDLE"  => "LibC::HANDLE",
  }

  # Runtime configuration parameters
  class_property log_file : Bool = false
  class_property log_file_name : Path = Path.new("winmd.log")
  class_property log_level : ::Log::Severity = ::Log::Severity::Warn
  class_property fun_handle : String = "comment"
  class_property output_dir : Path = Path.new("win32cr")
  class_property top_level_namespace : String = "Win32cr"
  class_property fun_exceptions_file : Path = Path.new("fun_exceptions.json")
  class_property dll_exceptions_file : Path = Path.new("dll_exceptions.json")
  class_property data_type_aliases_file : Path = Path.new("data_type_aliases.json")
  class_property overrides_file : Path = Path.new("overrides.json")
  class_property? fun_aliases : Bool = false
  # Compiler used to discover the LibC functions that must not be redeclared.
  class_property crystal_executable : String = ENV["WINMD_CRYSTAL"]? || "crystal"
  # Optional list of LibC function names that replaces discovery.
  class_property libc_funs_file : Path? = nil

  def self.init
    if ::File.exists?(@@dll_exceptions_file)
      begin
        json = JSON.parse(::File.read(@@dll_exceptions_file))
        json.as_a.each { |x| @@dll_exceptions << x.as_s }
      rescue e : Exception
        Log.fatal { "Failed to load DLL exceptions" }
        Log.fatal { e.message }
        Log.fatal { e.backtrace }
        exit 1
      end
    end
    DEFAULT_TYPE_ALIASES.each { |key, value| @@data_type_aliases[key] ||= value }
    if ::File.exists?(@@data_type_aliases_file)
      begin
        json = JSON.parse(::File.read(@@data_type_aliases_file))
        json.as_h.each { |key, value| @@data_type_aliases[key] = value.as_s }
      rescue e : Exception
        Log.fatal { "Failed to load data type aliases" }
        Log.fatal { e.message }
        Log.fatal { e.backtrace }
        exit 1
      end
    end
    WinMD::Fun.collect_funs
    WinMD::FunOverride.load_overrides(@@overrides_file)
    @@crystal_keywords = Crystal::Keyword.names.map { |x| x.downcase }
    @@crystal_keywords << "initialize"
    @@crystal_keywords << "finalize"
  end

  def self.dll_exception?(name : String)
    @@dll_exceptions.includes?(name)
  end

  def self.get_alias(name : String)
    @@data_type_aliases[name]
  end

  def self.has_alias?(name : String)
    @@data_type_aliases.has_key?(name)
  end

  def self.rename_type(name : String)
    if @@data_type_aliases.has_key?(name)
      return @@data_type_aliases[name]
    end
    name
  end

  def self.fix_type_name(name : String)
    name = name.sub(/^tag/, "")
    while /^_/.match(name)
      name = name.sub(/^_/, "")
      name += "_"
    end
    unless name[0].uppercase?
      name = name.capitalize
    end
    name
  end

  def self.fix_param_name(name : String)
    # No need to change if first char is already downcase
    name = name.underscore unless name[0].lowercase?
    if check_keyword(name)
      name = name + "__"
    end
    name
  end

  def self.check_keyword(name : String)
    @@crystal_keywords.includes?(name)
  end

  def self.fix_namespace(name : String) : Tuple(String, String)
    prefix = @@top_level_namespace
    path = prefix.downcase + "/" + name.downcase.gsub(".", "/")
    name = prefix + "::" + name.gsub(".", "::")
    unless /^#{prefix}/.match(name)
      name = prefix + "::" + name
    end
    return {name, path}
  end

  def self.add_file(file : File)
    unless files.includes?(file)
      @@files << file
    end
  end

  def self.find_file_by_ns(name : String)
    if file = @@files.find { |x| x.namespace == name }
      file
    end
  end

  def self.process_json_files(path : Path)
    Dir.glob(path).each do |f|
      data = ::File.read(f)
      begin
        file = WinMD::File.from_json(data, f)
        WinMD.add_file(file)
      rescue e : Exception
        puts "Error on file: #{f}"
        puts e.message
        puts e.backtrace
        exit 1
      end
    end
  end

  def self.process_winmd_file(path : Path, dump_dir : Path? = nil, associated_enums : Bool = false)
    begin
      parsed = Ecma335.parse(path.to_s)
      importer = WinMD::Ecma335Importer.new(parsed)
      importer.associated_enums = associated_enums
      if dump_dir
        Log.debug { "Dumping intermediate JSON to #{dump_dir}" }
        importer.dump(dump_dir)
      end
      importer.import.each do |file|
        WinMD.add_file(file)
      end
    rescue e : Exception
      puts "Error while processing WinMD file: #{path}"
      puts e.message
      puts e.backtrace
      exit 1
    end
  end

  def self.resolve_com_interfaces
    WinMD.files.each do |f|
      begin
        f.com_interfaces.each do |com|
          methods = com.resolve_methods.map(&.name).join(", ")
        end
      rescue
        next
      end
    end
  end

  # Renders every namespace file plus the library entry points into `dir`.
  # Failures are reported per file with the path involved; the process exits
  # with status 1 when any file could not be written so callers and CI notice.
  def self.write_files(dir : Path)
    failures = 0

    WinMD.files.each do |f|
      target = dir.join(f.file_path).join(f.file_name)
      begin
        f.file = f
        if f.empty_shell?
          Log.debug { "Skipping empty namespace shell #{f.namespace} (#{f.file_path}/#{f.file_name})" }
          next
        end
        content = f.render
        Dir.mkdir_p(dir.join(f.file_path))
        ::File.write(target, content)
      rescue e : Exception
        failures += 1
        report_write_failure(target, f.namespace, e)
      end
    end

    lib_name = WinMD.top_level_namespace.downcase
    {
      dir.join("src", "#{lib_name}.cr")           => "./src/winmd/ecr/library_main.ecr",
      dir.join("src", lib_name, "com_ptr.cr")     => "./src/winmd/ecr/com_ptr.ecr",
      dir.join("src", lib_name, "libc_bridge.cr") => "./src/winmd/ecr/libc_bridge.ecr",
    }.each do |target, template|
      begin
        Dir.mkdir_p(target.parent)
        ::File.write(target, render_template(template))
      rescue e : Exception
        failures += 1
        report_write_failure(target, nil, e)
      end
    end

    macros = dir.join("src", "macros.cr")
    unless ::File.exists?(macros)
      begin
        ::File.write(macros, render_template("./src/winmd/ecr/macros.ecr"))
      rescue e : Exception
        failures += 1
        report_write_failure(macros, nil, e)
      end
    end

    if failures > 0
      STDERR.puts "#{failures} file(s) could not be written to #{dir}"
      exit 1
    end
  end

  private def self.render_template(template : String) : String
    case template
    when "./src/winmd/ecr/library_main.ecr" then ECR.render("./src/winmd/ecr/library_main.ecr")
    when "./src/winmd/ecr/com_ptr.ecr"      then ECR.render("./src/winmd/ecr/com_ptr.ecr")
    when "./src/winmd/ecr/libc_bridge.ecr"  then ECR.render("./src/winmd/ecr/libc_bridge.ecr")
    when "./src/winmd/ecr/macros.ecr"       then ECR.render("./src/winmd/ecr/macros.ecr")
    else                                         raise ArgumentError.new("unknown template #{template}")
    end
  end

  private def self.report_write_failure(target : Path, namespace : String?, error : Exception) : Nil
    STDERR.puts "Failed to write #{target}#{namespace ? " (#{namespace})" : ""}: #{error.message}"
    if error.is_a?(::File::AccessDeniedError)
      STDERR.puts "  The path exists and is read-only, locked by another process, or is a directory."
    end
    Log.debug { error.backtrace.join("\n") }
  end

  def self.apply_overrides
    @@files.each do |f|
      if (size = WinMD::FunOverride.find_ns_overrides(f.namespace).size) > 0
        Log.debug { "{WinMD}Found #{size} overrides for #{f.namespace} - #{f.file_name}"}
        f.process_overrides
      end
    end
  end
end
