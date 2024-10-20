class WinMD::Fun

  class_getter funs = [] of WinMD::Fun
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
    funs = {{LibC.methods.map(&.stringify)}}
    funs.reject! { |x| x.size == 0 } 

    funs.each do |f|
      begin
        if _fun = parse_fun(f)
          if @@funs.includes?(_fun)
          else
            @@funs << _fun
          end

        end
      rescue e : Exception
        puts "Failed to parse fun for #{f}"
        puts e.message
        puts e.backtrace
        next
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
end