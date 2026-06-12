class WinMD::Fun
  class_getter funs = [] of WinMD::Fun
  # Exceptions will be treated as LibC funs
  class_getter exceptions = [] of String
  LIBC_FUN_REGEX = /^\s*fun\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*=\s*([A-Za-z_][A-Za-z0-9_]*))?/
  getter name : String
  getter params = [] of FunParam
  getter return_type : String?
  getter original_def : String

  def initialize(@name : String, @params : Array(FunParam), @original_def : String, @return_type : String | Nil = nil)
  end

  def ==(other : Fun)
    @name == other.name
  end

  def ==(other : String)
    @name == other
  end

  def file=(file)
    super(file)
    @params.each do |param|
      param.file = file
      if param.type.is_a?(WinMD::Type::ApiRef)
        inc = WinMD::Include.new(param.type.as(WinMD::Type::ApiRef).api, file)
        file.add_include(inc)
      end
    end
  end

  def self.parse_fun(fun_def : String) : WinMD::Fun
    if fun_match = /^(\s+)?fun (?'fun_name'[a-zA-Z0-9_]+)/.match(fun_def)
      fun_obj = new(fun_match["fun_name"], [] of WinMD::FunParam, fun_def, nil)
      fun_obj
    else
      raise Exception.new("Could not match against fun: #{fun_def}")
    end
  end

  def self.collect_funs
    if ::File.exists?(WinMD.fun_exceptions_file)
      json = JSON.parse(::File.read(WinMD.fun_exceptions_file))
      json.as_a.each { |x| @@exceptions << x.as_s }
    end
    funs = {{LibC.methods.map(&.stringify)}}
    funs.reject! { |x| x.size == 0 }

    funs.each do |f|
      begin
        if _fun = parse_fun(f)
          unless @@exceptions.includes?(_fun.name)
            @@exceptions << _fun.name
          end
        end
      rescue e : Exception
        puts "Failed to parse fun for #{f}"
        puts e.message
        puts e.backtrace
        next
      end
    end

    collect_stdlib_libc_funs.each do |name|
      unless @@exceptions.includes?(name)
        @@exceptions << name
      end
    end
  end

  def self.find_fun(name : String)
    @@funs.find do |x|
      if x.name == name
        x
      else
        next
      end
    end
  end

  def self.exception?(name : String)
    @@exceptions.includes?(name)
  end

  private def self.collect_stdlib_libc_funs : Array(String)
    crystal_paths = crystal_path_entries
    return [] of String if crystal_paths.empty?

    fun_names = [] of String
    crystal_paths.each do |entry|
      collect_stdlib_libc_funs_from_entry(entry, fun_names)
    end

    fun_names.uniq
  rescue
    [] of String
  end

  private def self.crystal_path_entries : Array(String)
    output = IO::Memory.new
    status = Process.run("crystal", ["env", "CRYSTAL_PATH"], output: output, error: Process::Redirect::Close)
    return [] of String unless status.success?

    raw = output.to_s.strip
    return [] of String if raw.empty?

    separator = {{ flag?(:win32) ? ";" : ":" }}
    raw.split(separator).map(&.strip).reject(&.empty?)
  rescue
    [] of String
  end

  private def self.collect_stdlib_libc_funs_from_entry(path_entry : String, fun_names : Array(String)) : Nil
    root = Path.new(path_entry)
    candidates = [] of Path
    candidates << root.join("lib_c")
    candidates << root.join("src", "lib_c")

    candidates.each do |candidate|
      next unless Dir.exists?(candidate)
      glob_base = candidate.to_s.gsub('\\', '/')
      Dir.glob("#{glob_base}/**/c/*.cr").each do |file_path|
        collect_fun_names_from_file(file_path, fun_names)
      end
    end
  end

  private def self.collect_fun_names_from_file(file_path : String, fun_names : Array(String)) : Nil
    ::File.each_line(file_path) do |line|
      next unless match = LIBC_FUN_REGEX.match(line)
      fun_names << match[1]
      if alias_name = match[2]?
        fun_names << alias_name
      end
    end
  rescue
    # Best-effort only: keep generating even if one stdlib file is unreadable.
  end
end
