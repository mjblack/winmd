class WinMD::Fun
  class_getter funs = [] of WinMD::Fun
  # Functions that Crystal's own LibC already declares (or that the user
  # listed in fun_exceptions.json). The generator comments these out instead
  # of redeclaring them.
  class_getter exceptions = [] of String
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

  # Builds the exception list: fun_exceptions.json plus the LibC functions of
  # the Crystal that will compile the bindings, discovered at run time
  # (`WinMD::LibCFuns.discover`) or read from `WinMD.libc_funs_file`.
  def self.collect_funs
    @@exceptions.clear
    if ::File.exists?(WinMD.fun_exceptions_file)
      json = JSON.parse(::File.read(WinMD.fun_exceptions_file))
      json.as_a.each { |x| add_exception(x.as_s) }
    end

    libc = if file = WinMD.libc_funs_file
             Log.debug { "Reading LibC function names from #{file}" }
             WinMD::LibCFuns.load_list(file)
           else
             WinMD::LibCFuns.discover
           end
    Log.debug { "#{libc.size} LibC functions will not be redeclared" }
    libc.each { |name| add_exception(name) }
  end

  def self.find_fun(name : String)
    @@funs.find { |x| x.name == name }
  end

  def self.exception?(name : String)
    @@exceptions.includes?(name)
  end

  private def self.add_exception(name : String)
    @@exceptions << name unless @@exceptions.includes?(name)
  end
end
