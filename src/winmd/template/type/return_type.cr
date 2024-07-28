class WinMD::Type::ReturnType < WinMD::Type

  @[JSON::Field(key: "Name")]
  property name : String?

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "TargetKind")]
  property target_kind : String?

  @[JSON::Field(key: "Api")]
  property api : String?

  @[JSON::Field(key: "Parents")]
  property parents = [] of String

  @[JSON::Field(key: "Child")]
  property child : WinMD::Type?

  def file=(file : WinMD::File)
    super(file)
    if c = @child
      c.file = file
    end
  end
end