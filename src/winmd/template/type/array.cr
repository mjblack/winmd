class WinMD::Type::Array < WinMD::Type
  @[JSON::Field(key: "Shape")]
  property _shape : Nil | Hash(String, Int32)

  @[JSON::Field(ignore: true)]
  property shape = {} of String => Int32

  @[JSON::Field(ignore: true)]
  property size : Int32 = 0

  @[JSON::Field(key: "Child")]
  property child : WinMD::Type

  def render
    ECR.render "./src/winmd/ecr/array.ecr"
  end

  def after_initialize
    if @_shape.nil?
      @shape = {} of String => Int32
      @shape["Size"] = 0
    else
      if @_shape.as(Hash(String, Int32)).has_key?("Size")
        @shape["Size"] = @_shape.as(Hash(String, Int32))["Size"]
      end
    end
    @size = Int32.new(@shape["Size"])
  end

  def file=(file : WinMD::File)
    super(file)
    if c = @child
      c.file = file
    end
  end
  
  def nested_type=(value : Bool)
    @nested_type = value
    @child.nested_type = value
  end
end
