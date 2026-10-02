# Discovers the C functions that the installed Crystal's standard library
# declares in `lib LibC` for the target platform, so the generator can avoid
# redeclaring them (a `fun` with the same name in another `lib` is a
# redefinition error when both end up in one program).
#
# The list is read from the compiler found on PATH (or `WINMD_CRYSTAL`) at
# generation time rather than baked into winmd, so it always matches the
# Crystal that will compile the bindings. It covers every declaration under
# `src/lib_c/<target>/` plus the platform's `src/crystal/system/<os>/` files,
# not just what a minimal program's prelude happens to require: which stdlib
# files a user's program pulls in cannot be known here, so any name Crystal
# declares for the target is treated as taken.
module WinMD::LibCFuns
  class Error < Exception
  end

  FUN_DECLARATION = /^\s*fun\s+([A-Za-z_][A-Za-z0-9_]*)/

  # Names of all `fun`s declared for `target` by the stdlib of `crystal`.
  def self.discover(crystal : String = WinMD.crystal_executable, target : String? = nil) : Array(String)
    stdlib = stdlib_source(crystal)
    triple = target || default_target(crystal)
    dir = lib_c_directory(stdlib, triple)

    # Dir.glob needs forward slashes in the whole pattern, even on Windows.
    files = Dir.glob("#{posix(dir)}/**/*.cr")
    system_dir = stdlib.join("crystal", "system", system_subdir(triple))
    if Dir.exists?(system_dir)
      files += Dir.glob("#{posix(system_dir)}/**/*.cr")
    end

    names = Set(String).new
    files.each do |file|
      ::File.each_line(file) do |line|
        if match = FUN_DECLARATION.match(line)
          names << match[1]
        end
      end
    end
    names.to_a.sort
  end

  # One name per line, `#` comments allowed; used instead of discovery when
  # the generator must run without a Crystal compiler available.
  def self.load_list(path : Path) : Array(String)
    ::File.read_lines(path).compact_map do |line|
      text = line.strip
      next if text.empty? || text.starts_with?('#')
      text
    end
  end

  # `src` directory of the stdlib: the CRYSTAL_PATH entry that holds lib_c.
  def self.stdlib_source(crystal : String) : Path
    raw = run(crystal, ["env", "CRYSTAL_PATH"]).strip.strip('"')
    separator = raw.includes?(';') ? ';' : ':'
    raw.split(separator).map(&.strip.strip('"')).reject(&.empty?).each do |entry|
      candidate = Path.new(entry)
      return candidate if Dir.exists?(candidate.join("lib_c"))
    end
    raise Error.new("Could not find Crystal's standard library (no lib_c in CRYSTAL_PATH #{raw.inspect})")
  end

  # Target triple reported by `crystal --version`, e.g. x86_64-pc-windows-msvc.
  def self.default_target(crystal : String) : String
    run(crystal, ["--version"]).each_line do |line|
      if match = /Default target:\s*(\S+)/.match(line)
        return match[1]
      end
    end
    raise Error.new("Could not determine the default target from `#{crystal} --version`")
  end

  # `src/lib_c/<dir>` for a target triple. Crystal names these directories
  # without the vendor part: x86_64-pc-windows-msvc -> x86_64-windows-msvc,
  # aarch64-apple-darwin -> aarch64-darwin, x86_64-unknown-linux-gnu ->
  # x86_64-linux-gnu.
  def self.lib_c_directory(stdlib : Path, triple : String) : Path
    candidates = [lib_c_directory_name(triple), triple].uniq
    candidates.each do |name|
      dir = stdlib.join("lib_c", name)
      return dir if Dir.exists?(dir)
    end
    raise Error.new("No lib_c directory for target #{triple} under #{stdlib.join("lib_c")} (tried #{candidates.join(", ")})")
  end

  def self.lib_c_directory_name(triple : String) : String
    parts = triple.split('-')
    case parts.size
    when 4 then "#{parts[0]}-#{parts[2]}-#{parts[3]}"
    when 3 then "#{parts[0]}-#{parts[2]}"
    else        triple
    end
  end

  # Platform-specific stdlib sources that also declare LibC functions.
  def self.system_subdir(triple : String) : String
    triple.includes?("windows") ? "win32" : "unix"
  end

  private def self.posix(path : Path) : String
    path.to_s.gsub('\\', '/')
  end

  private def self.run(crystal : String, args : Array(String)) : String
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run(crystal, args, output: output, error: error)
    unless status.success?
      raise Error.new("`#{crystal} #{args.join(" ")}` failed: #{error.to_s.strip}")
    end
    output.to_s
  rescue e : IO::Error
    # Includes ::File::NotFoundError when the executable does not exist.
    raise Error.new("Could not run the Crystal compiler `#{crystal}` (#{e.message}); set WINMD_CRYSTAL or use --libc-funs FILE")
  end
end
