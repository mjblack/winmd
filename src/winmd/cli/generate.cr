module WinMD
  class CLI
    class Generate < Admiral::Command

      define_help description: "WinMD Generator"
      define_version WinMD::VERSION

      define_flag handle_fun : String,
                  description: "How to handle duplicate funs (coment, copy, none)",
                  default: "comment",
                  short: f,
                  long: "fun-handler"

      define_flag output_dir : String,
                  description: "Location to output generated crystal files.",
                  default: ""

      define_argument source_dir : String,
                      description: "Source directory with JSON files",
                      required: true

      define_argument dest_dir : String,
                      description: "Destination directory for rendered Crystal library",
                      required: true,
                      default: "win32cr"

      def run

        case flags.handle_fun
        when "comment", "copy", "none"
          WinMD.fun_handle = flags.handle_fun
        else
          exit 1
        end


        src = Path.new(arguments.source_dir)
        dst = Path.new(arguments.dest_dir)

        #files = [] of WinMD::TFile
        json_path = Path.new(src).join("**/*.json")

        WinMD.init
        WinMD.process_json_files(json_path)
        WinMD.resolve_com_interfaces
        WinMD.write_files(dst)
      end
    end

    register_sub_command generate : Generate, "Generate Win32 projection based on supplied metadata"
  end
end