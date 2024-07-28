class WinMD::Method < WinMD::Base
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "SetLastError")]
  property set_last_error : Bool | Nil

  @[JSON::Field(key: "ReturnType")]
  property return_type : WinMD::Type

  @[JSON::Field(key: "ReturnAttrs")]
  property return_attrs = [] of String

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "Params")]
  property params = [] of WinMD::Param

  @[JSON::Field(ignore: true)]
  property interface : String = ""

  def after_initialize
    @name = WinMD.fix_param_name(@name)
    super
  end

  def file=(file : WinMD::File)
    super(file)
    @return_type.file = file
    @params.each do |x|
      x.file = file
      if x.type.is_a?(WinMD::Type::ApiRef)
        inc = WinMD::Include.new(x.type.as(WinMD::Type::ApiRef).api, file)
        file.add_include(inc)
      elsif x.type.is_a?(WinMD::Type::PointerTo) && x.type.as(WinMD::Type::PointerTo).child.is_a?(WinMD::Type::ApiRef)
        inc = WinMD::Include.new(x.type.as(WinMD::Type::PointerTo).child.as(WinMD::Type::ApiRef).api, file)
        file.add_include(inc)
      end
    end
  end

  def render_proc
    render_proc(@interface)
  end

  def render_proc(interface_name : String)
    ECR.render "./src/winmd/ecr/method_proc.ecr"
  end

  def render
    render(@interface)
  end

  def render(interface_name : String)
    ECR.render "./src/winmd/ecr/method.ecr"
  end
end