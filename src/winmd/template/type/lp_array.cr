class WinMD::Type::LPArray < WinMD::Type

  @[JSON::Field(key: "NullNullTerm")]
  property null_null_term : Bool

  @[JSON::Field(key: "CountConst", converter: String::RawConverter, ignore_serialize: true)]
  property count_const : String | UInt32

  @[JSON::Field(key: "CountParamIndex", converter: String::RawConverter, ignore_serialize: true)]
  property count_param_index : String | Int32

  @[JSON::Field(key: "Child")]
  property child : Type

  def render
    ECR.render "./src/winmd/ecr/lp_array.ecr"
  end

  def after_initialize
    super
    if @count_param_index.is_a?(String)
      begin
        @count_param_index = @count_param_index.to_i32
      rescue e : Exception
        puts "LPArray - after_initialize - count_param_index: failed to convert String to UInt32"
        puts e.message
        puts e.backtrace
      end
    end
  end

  def file=(file : File)
    super(file)
    @child.file = file
  end

end