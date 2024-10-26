class WinMD::Function < WinMD::Base
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "SetLastError")]
  property set_last_error : Bool | Nil

  @[JSON::Field(key: "DllImport")]
  property dll_import : String

  @[JSON::Field(key: "ReturnType")]
  property return_type : WinMD::Type

  @[JSON::Field(key: "ReturnAttrs")]
  property return_attrs = [] of String

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "Params")]
  property params = [] of WinMD::Param

  @[JSON::Field(ignore: true)]
  getter libc_fun : Bool = false


  def after_initialize
    super
    if WinMD::Fun.exception?(@name)
      @libc_fun = true
    end
    @dll_import = @dll_import.downcase
  end

  def file=(file : WinMD::File)
    super(file)
    @return_type.file = file
    @params.each { |x| x.file = file }
  end

  def render
    ECR.render "./src/winmd/ecr/function.ecr"
  end
end