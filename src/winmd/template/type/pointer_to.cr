class WinMD::Type::PointerTo < WinMD::Type


  @[JSON::Field(key: "Child")]
  property child : WinMD::Type

  def file=(file : File)
    super(file)
    @child.file = file
    if @child.is_a?(WinMD::Type::ApiRef)
      inc = WinMD::Include.new(@child.as(WinMD::Type::ApiRef).api, file)
      file.add_include(inc)
    end
  end

  def render
    ECR.render "./src/winmd/ecr/pointer_to.ecr"
  end

  def nested_type=(value)
    @nested_type = value
    @child.nested_type = value
  end

end