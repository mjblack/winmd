module WinMD
  class CLI
    # Prints the LibC function names the generator will not redeclare, as
    # discovered from the installed Crystal. Useful to see why a function was
    # commented out, or to capture a list for --libc-funs.
    class Libc < Admiral::Command
      define_help description: "List the LibC functions Crystal's stdlib declares for the target"
      define_version WinMD::VERSION

      define_flag target : String,
        description: "Target triple (default: the compiler's default target)",
        long: "target",
        default: ""

      def run
        names = WinMD::LibCFuns.discover(WinMD.crystal_executable, flags.target.empty? ? nil : flags.target)
        names.each { |name| puts name }
      rescue e : WinMD::LibCFuns::Error
        STDERR.puts e.message
        exit 1
      end
    end

    register_sub_command libc : Libc, "List the LibC functions that will not be redeclared"
  end
end
