module WinMD
  class FunParam
    getter name : String = ""
    getter type : WinMD::Type
    getter index : Int32 = 0

    def initialize(@name : String, @type : String, @index : Int32)
    end

    # Check if name and type match but if they're different but same index
    # then raise error.
    def ==(other : FunParam)
      if @name == other.name && @type == other.type && @index == other.index
        true
      elsif @index == other.index
        raise Exception.new("Fun Param was different but index the same")
      end
    end

    def to_s(io)
      io << "Param name "
      io << @name
      io << ", type is "
      io << @type
    end

    def render
      ECR.render "./src/winmd/ecr/fun_param.ecr"
    end

    def file=(file : WinMD::File)
      super(file)
      @type.file = file
    
      if @type.is_a?(WinMD::Type::ApiRef)
        inc = WinMD::Include.new(@type.as(WinMD::Type::ApiRef).api, file)
        file.add_include(inc)
      elsif @type.is_a?(WinMD::Type::PointerTo)
        if @type.as(WinMD::Type::PointerTo).child.is_a?(WinMD::Type::ApiRef)
          inc = WinMD::Include.new(@type.as(WinMD::Type::PointerTo).child.as(WinMD::Type::ApiRef).api, file)
          file.add_include(inc)
        end
      end
    end
  end
end