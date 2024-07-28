module WinMD::Architecture
  ALIASES = {
    "X86" => "i386",
    "X64" => "x86_64",
    "Arm64" => "arm"
  }

  def architectures?
    @architectures.any?
  end

  def render_arches
    a = @architectures.map do |x|
      if ALIASES.has_key?(x)
        str = "flag?(:" + ALIASES[x] + ")"
        str
      end
    end.compact
    a
  end
end