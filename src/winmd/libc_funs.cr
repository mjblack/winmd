# Discovers the C functions that the installed Crystal's standard library
# declares in `lib LibC` for the target platform, so the generator can avoid
# redeclaring them (a `fun` with the same C name in another `lib` is a
# redefinition error unless the signatures are identical).
#
# The list is read from the compiler found on PATH (or `WINMD_CRYSTAL`) at
# generation time rather than baked into winmd, so it always matches the
# Crystal that will compile the bindings. It covers every declaration under
# `src/lib_c/<target>/` plus the platform's `src/crystal/system/<os>/` files,
# not just what a minimal program's prelude happens to require: which stdlib
# files a user's program pulls in cannot be known here, so any name Crystal
# declares for the target is treated as taken.
#
# Each declaration is parsed with Crystal's own parser so the generator also
# knows the parameter and return types LibC uses. With those it can emit a
# wrapper that forwards to the stdlib declaration instead of only commenting
# the function out (see `WinMD::Function#libc_call`).
module WinMD::LibCFuns
  class Error < Exception
  end

  record Param, name : String, type : String

  # One `fun` of the stdlib. Type names are spelled so they resolve from
  # generated code (`::LibC::FILETIME`, `Pointer(Void)`, `Proc(...)`).
  # `params` is nil when the declaration could not be parsed, in which case
  # only the name is known.
  record Signature,
    name : String,
    real_name : String,
    lib_name : String,
    params : Array(Param)?,
    return_type : String,
    require_path : String,
    varargs : Bool = false do
    def to_s(io : IO) : Nil
      io << name
      io << " = " << real_name if real_name != name
      if (params = @params) && !params.empty?
        io << '('
        params.join(io, ", ") { |param, inner| inner << param.name << " : " << param.type }
        io << ", ..." if varargs
        io << ')'
      end
      io << " : " << return_type
    end
  end

  FUN_DECLARATION = /^\s*fun\s+([A-Za-z_][A-Za-z0-9_]*)/

  # C symbol names of all `fun`s declared for `target` by the stdlib of `crystal`.
  def self.discover(crystal : String = WinMD.crystal_executable, target : String? = nil) : Array(String)
    discover_signatures(crystal, target).keys.sort
  end

  # Signatures of all `fun`s declared for `target`, keyed by C symbol name
  # (the name a generated `fun` would collide with).
  def self.discover_signatures(crystal : String = WinMD.crystal_executable, target : String? = nil) : Hash(String, Signature)
    stdlib = stdlib_source(crystal)
    triple = target || default_target(crystal)
    dir = lib_c_directory(stdlib, triple)

    sources = read_sources(dir, dir)
    system_dir = stdlib.join("crystal", "system", system_subdir(triple))
    sources += read_sources(system_dir, stdlib) if Dir.exists?(system_dir)

    signatures = {} of String => Signature
    parse_sources(sources).each do |signature|
      signatures[signature.real_name] ||= signature
    end
    signatures
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

  # Parses Crystal sources (`{source, require_path}` pairs) and returns every
  # `fun` declared inside a `lib`.
  #
  # Declarations the parser does not see, because the file uses syntax newer
  # than the parser built into winmd or because the `fun` sits inside a
  # `{% if flag?(...) %}` block (whose body is only expanded by the compiler),
  # are still found by a textual scan and reported with their name only, so
  # they are not redeclared even though no wrapper can be generated.
  def self.parse_sources(sources : Array({String, String})) : Array(Signature)
    signatures = [] of Signature
    sources.each do |source, require_path|
      collector = Collector.new
      begin
        Crystal::Parser.parse(source).accept(collector)
      rescue e : Crystal::SyntaxException
        Log.warn { "Could not parse #{require_path} (#{e.message}); its functions will only be commented out" }
      end

      parsed = collector.entries.map do |entry|
        fun_def = entry.fun_def
        params = [] of Param
        fun_def.args.each do |arg|
          restriction = arg.restriction
          if restriction
            params << Param.new(arg.name, type_text(restriction, entry.lib_name))
          else
            params = nil
            break
          end
        end
        return_type = (rt = fun_def.return_type) ? type_text(rt, entry.lib_name) : "Void"
        Signature.new(fun_def.name, fun_def.real_name, entry.lib_name, params, return_type, require_path, fun_def.varargs?)
      end
      signatures.concat(parsed)

      seen = parsed.map(&.name).to_set
      source.each_line do |line|
        if (match = FUN_DECLARATION.match(line)) && !seen.includes?(match[1])
          real_name = (alias_match = /^\s*fun\s+#{match[1]}\s*=\s*([A-Za-z_][A-Za-z0-9_]*)/.match(line)) ? alias_match[1] : match[1]
          signatures << Signature.new(match[1], real_name, "LibC", nil, "Void", require_path)
        end
      end
    end
    signatures
  end

  def self.parse_source(source : String, require_path : String) : Array(Signature)
    parse_sources([{source, require_path}])
  end

  # Crystal's own types, which a bare name inside a `lib` still refers to.
  # Anything else written without a namespace (`DWORD`, `Int`, `SizeT`,
  # `ULONG_PTR`) is a type the lib declares, possibly in another file or
  # inside a `{% if flag?(...) %}` block the parser does not expand.
  PRIMITIVE_TYPES = Set{
    "Void", "Nil", "Bool",
    "Int8", "Int16", "Int32", "Int64", "Int128",
    "UInt8", "UInt16", "UInt32", "UInt64", "UInt128",
    "Float32", "Float64",
    "Pointer", "StaticArray", "Proc", "Tuple",
  }

  # Spells a type restriction from a lib declaration so it resolves from
  # generated code: names the lib declares get an absolute lib prefix, and
  # `Foo*` / `-> Bar` become `Pointer(Foo)` / `Proc(Bar)`, which are valid
  # where a type is used as a value.
  def self.type_text(node : Crystal::ASTNode, lib_name : String) : String
    case node
    when Crystal::Path
      names = node.names
      if names.size == 1 && !node.global? && !PRIMITIVE_TYPES.includes?(names[0])
        "::#{lib_name}::#{names[0]}"
      elsif names.size > 1 && !node.global?
        # `LibC::ULONG` written inside another lib: absolute, so it cannot be
        # captured by a namespace of the generated code.
        "::#{names.join("::")}"
      else
        names.join("::")
      end
    when Crystal::Generic
      args = node.type_vars.map { |arg| type_text(arg, lib_name) }
      "#{type_text(node.name, lib_name)}(#{args.join(", ")})"
    when Crystal::ProcNotation
      inputs = (node.inputs || [] of Crystal::ASTNode).map { |input| type_text(input, lib_name) }
      output = (result = node.output) ? type_text(result, lib_name) : "Nil"
      "Proc(#{(inputs + [output]).join(", ")})"
    else
      node.to_s
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

  # Every .cr file under `dir` with the path a `require` needs to load it,
  # relative to `root` (`c/heapapi` for lib_c files, `crystal/system/...`
  # for the rest).
  private def self.read_sources(dir : Path, root : Path) : Array({String, String})
    # Dir.glob needs forward slashes in the whole pattern, even on Windows.
    Dir.glob("#{posix(dir)}/**/*.cr").sort.map do |file|
      require_path = posix(Path.new(file).relative_to(root)).rchop(".cr")
      {::File.read(file), require_path}
    end
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

  # Collects the `fun`s of every `lib` in a parsed source, including those
  # inside `{% if ... %}` blocks: the parser keeps such a block's body as
  # text, so the body is parsed again here as the content of the same lib.
  # Both branches are collected; for the same C name the first declaration
  # found wins, which is the `then` branch.
  private class Collector < Crystal::Visitor
    record Entry, lib_name : String, fun_def : Crystal::FunDef

    getter entries = [] of Entry
    @libs = [] of String

    def visit(node : Crystal::LibDef)
      @libs << node.name.names.join("::")
      true
    end

    def end_visit(node : Crystal::LibDef)
      @libs.pop
    end

    def visit(node : Crystal::FunDef)
      if lib_name = @libs.last?
        @entries << Entry.new(lib_name, node)
      end
      false
    end

    def visit(node : Crystal::MacroIf)
      if lib_name = @libs.last?
        [node.then, node.else].each do |branch|
          collect_macro_body(branch, lib_name)
        end
      end
      false
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def collect_macro_body(branch : Crystal::ASTNode, lib_name : String)
      text = String.build { |io| macro_text(branch, io) }
      return if text.blank?
      begin
        Crystal::Parser.parse("lib #{lib_name}\n#{text}\nend").accept(self)
      rescue Crystal::SyntaxException
        # Not a plain list of declarations (nested macro code, for example);
        # the textual scan in parse_sources still picks up the names.
      end
    end

    private def macro_text(node : Crystal::ASTNode, io : IO) : Nil
      case node
      when Crystal::MacroLiteral then io << node.value
      when Crystal::Expressions  then node.expressions.each { |e| macro_text(e, io) }
      else                            # macro expressions and nested conditionals cannot be expanded here
      end
    end
  end
end
