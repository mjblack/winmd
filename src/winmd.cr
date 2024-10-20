require "log"
require "json"
require "yaml"
require "ecr"
require "big"
require "uuid"
require "file_utils"
require "compiler/crystal/syntax/ast"
require "compiler/crystal/syntax/virtual_file"
require "compiler/crystal/syntax/lexer"
require "compiler/crystal/syntax/token"

require "admiral"
require "git-repository"

require "./winmd/fun_param"
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

module WinMD
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  LIBC_FUNS = {{LibC.methods.map  do |x|
                  args = x.args.stringify.gsub(/[\[|\]]/, "").split(",")
                  {name: x.name.stringify, args: args, return_type: x.return_type.stringify}
                end
              }}

  DATA_TYPES_ALIASES = {
    "Char"    => "UInt16",
    "Single"  => "Float32",
    "Double"  => "Float64",
    "SByte"   => "Int8",
    "Byte"    => "UInt8",
    "Guid"    => "LibC::GUID",
    "UIntPtr" => "LibC::UIntPtrT",
    "IntPtr"  => "LibC::IntPtrT",
    "Boolean" => "Bool"
  }

  INT_TYPES = {{Int.subclasses.map { |x| x.stringify }}}

  class_property files = [] of File
  class_property libc_funs = [] of WinMD::Fun
  class_property crystal_keywords = [] of String

  # Runtime configuration parameters
  class_property log_file : Bool = false
  class_property log_file_name : Path = Path.new("winmd.log")
  class_property log_level : ::Log::Severity = ::Log::Severity::Warn
  class_property fun_handle : String = "comment"
  class_property output_dir : Path = Path.new("win32cr")
  class_property top_level_namespace : String = "Win32cr"

  def self.init
    WinMD::Fun.collect_funs
    @@crystal_keywords = Crystal::Keyword.names.map { |x| x.downcase }
    @@crystal_keywords << "initialize"
    @@crystal_keywords << "finalize"
  end

  def self.rename_type(name : String)
    if DATA_TYPES_ALIASES.has_key?(name)
      return DATA_TYPES_ALIASES[name]
    end
    name
  end

  def self.fix_type_name(name : String)
    name = name.sub(/^tag/, "")
    while /^_/.match(name)
      name = name.sub(/^_/, "")
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

  def self.write_files(dir : Path)
    WinMD.files.each do |f|
      begin
        f.file = f
        file_dir = dir.join(f.file_path)
        Dir.mkdir_p(file_dir)
        ::File.open(file_dir.join(f.file_name), "w") do |fp|
          fp.write(f.render.to_slice)
        end
      rescue e : Exception
        puts e.message
        puts e.backtrace
      end
    end

    begin
      main_file_slice = ECR.render("./src/winmd/ecr/library_main.ecr").to_slice
      ::File.open(dir.join("src/" + WinMD.top_level_namespace.downcase + ".cr"), "w") do |f|
        f.write_string(main_file_slice)
        f.close
      end
    rescue e : Exception
      puts "Failed to create main file"
      puts e.message
      puts e.backtrace
    end
  end

end