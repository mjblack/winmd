class WinMD::Type::Union < WinMD::Type::Struct

  def after_initialize
    @union = true
    super
  end
end