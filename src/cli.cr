require "./winmd"
class WinMD::CLI < Admiral::Command

  define_help description: "WinMD parser and generator"
  define_version WinMD::VERSION

  def run
    puts help
  end
end

require "./winmd/cli/**"

WinMD::CLI.run