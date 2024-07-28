class WinMD::Param < WinMD::Base

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Type")]
  property type : WinMD::Type

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String | WinMD::Type

  def after_initialize
    @name = WinMD.fix_param_name(@name)
    super
    if @type.is_a?(WinMD::Type::PointerTo)
      if @type.as(WinMD::Type::PointerTo).child.is_a?(WinMD::Type::ApiRef)
        if @type.as(WinMD::Type::PointerTo).child.as(WinMD::Type::ApiRef).name == "IXMLElement"
          puts "We have IXMLElement"
        end
      end
    end
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

  def render_comment
    ECR.render "./src/winmd/ecr/param_comment.ecr"
  end

  def render_proc
    ECR.render "./src/winmd/ecr/param_proc.ecr"
  end

  def render
    ECR.render "./src/winmd/ecr/param.ecr"
  end
end