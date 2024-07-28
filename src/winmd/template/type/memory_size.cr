class WinMD::Type::MemorySize < WinMD::Type

  @[JSON::Field(key: "BytesParamIndex")]
  property bytes_param_index : Int32

  def render
    ECR.render "./src/winmd/ecr/memory_size.ecr"
  end
end