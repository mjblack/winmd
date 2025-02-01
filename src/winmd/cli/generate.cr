module WinMD
  class CLI
    class Generate < Admiral::Command
      @debug : Bool = false

      define_help description: "WinMD Generator"
      define_version WinMD::VERSION

      define_flag handle_fun : String,
        description: "How to handle duplicate funs (coment, copy, none)",
        default: "comment",
        short: f,
        long: "fun-handler"

      define_flag module_name : String,
        description: "Namespace to use",
        short: n,
        long: "module-name",
        default: "win32cr"

      define_flag debug : Bool,
        description: "Debug logging",
        default: false,
        short: d,
        long: debug

      define_argument source_dir : String,
        description: "Source directory with JSON files",
        required: false

      define_argument dest_dir : String,
        description: "Destination directory for rendered Crystal library. Source files will be in $DEST_DIR/src/$MODULE_NAME",
        required: false,
        default: "win32cr"

      def run
        case flags.handle_fun
        when "comment", "copy", "none"
          WinMD.fun_handle = flags.handle_fun
        else
          exit 1
        end

        @debug = flags.debug

        Log.setup do |c|
          backend = Log::IOBackend.new(dispatcher: :sync)
          log_level = @debug ? Log::Severity::Debug : Log::Severity::Fatal

          c.bind "*", log_level, backend
        end

        Log.debug { "WinMD starting up" }
        WinMD.top_level_namespace = flags.module_name.capitalize
        WinMD.output_dir = Path.new(flags.module_name.downcase)
        src = begin
          if str = arguments.source_dir
            Path.new(str)
          else
            puts "Error: Must supply source directory"
            puts help
            exit 1
          end
        end
        dst = begin
          if str = arguments.dest_dir
            Path.new(str)
          else
            puts "Error: Must supply destination directory"
            puts help
            exit 1
          end
        end

        Log.debug { "Source JSON directory: #{src.to_s}" }
        Log.debug { "Top level namespace: #{WinMD.top_level_namespace}" }
        Log.debug { "Output directory: #{dst.to_s}\\src\\#{WinMD.output_dir}" }

        # files = [] of WinMD::TFile
        json_path = Path.new(src).join("**/*.json")

        elapsed_time = Time.measure do
          Log.debug { "Initialized" }
          WinMD.init
          Log.debug { "Phase 1 - Processing JSON Files" }
          WinMD.process_json_files(json_path)
          Log.debug { "Phase 2 - Resolving COM Interfaces" }
          WinMD.resolve_com_interfaces
          Log.debug { "Phase 3 - Applying Overrides" }
          WinMD.apply_overrides
          Log.debug { "Phase 4 - Writing Files" }
          WinMD.write_files(dst)
        end
        Log.debug { "Total time taken #{elapsed_time}" }
      end
    end

    register_sub_command generate : Generate, "Generate Win32 projection based on supplied metadata"
  end
end
