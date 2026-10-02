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

      define_flag signatures : Bool,
        description: "Also print each declaration (parameters, return type, declaring stdlib file)",
        long: "signatures",
        default: false

      def run
        target = flags.target.empty? ? nil : flags.target
        signatures = WinMD::LibCFuns.discover_signatures(WinMD.crystal_executable, target)
        signatures.keys.sort.each do |name|
          if flags.signatures
            puts "#{signatures[name]}  [#{signatures[name].require_path}]"
          else
            puts name
          end
        end
      rescue e : WinMD::LibCFuns::Error
        STDERR.puts e.message
        exit 1
      end
    end

    register_sub_command libc : Libc, "List the LibC functions that will not be redeclared"
  end
end
