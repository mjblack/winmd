@[JSON::Serializable::Options(presence: true, emit_nulls: true)]
abstract class WinMD::Type < WinMD::Base


  use_json_discriminator "Kind", {"Enum": Enum, "FunctionPointer": FunctionPointer,
                                  "NativeTypedef": NativeTypedef, "Union": Union,
                                  "Struct": Struct, "Com": Com, "PointerTo": PointerTo,
                                  "ApiRef": ApiRef, "Native": Native,
                                  "ComClassID": ComClassID, "MemorySize": MemorySize,
                                  "LPArray": LPArray, "Array": Array, "Interface": Interface,
                                  "FreeWith": FreeWidth, "MissingClrType": MissingClrType }


  @[JSON::Field(key: "Kind")]
  property kind : String


  def render
    true
  end

  def apply_overrides
  end

  def apply_overrides(overrides = [] of WinMD::FunOverride)
  end

  def file=(file : WinMD::File)
    super(file)
  end
end

require "./type/*"