module WinMD
  class CLI
    class Lookup < Admiral::Command

      define_help description: "WinMD Datatype Lookup"
      define_version WinMD::VERSION

      define_argument source_dir : String,
                      description: "Source directory with JSON files",
                      required: true

      define_argument filename : String,
                      description: "File to lookup",
                      required: false

      define_argument datatype_kind : String,
                      description: "Data type kind to lookup",
                      required: false

      define_argument datatype_name : String,
                      description: "Data type name to lookup",
                      required: false


      def get_file_list
        WinMD.files.map do |file|
          path = Path.new(file.file_path).join(file.file_name)
        end.sort
      end

      def get_file_datatype_kinds
      end

      def get_file_datatype
      end

      def run
        src = Path.new(arguments.source_dir)
        file = arguments.get?(:filename)
        kind = arguments.get?(:datatype_kind)
        name = arguments.get?(:datatype_name)

        json_path = Path.new(src).join("**/*.json")

        WinMD.init
        WinMD.process_json_files(json_path)
        WinMD.resolve_com_interfaces

        unless file
          list = get_file_list.join("\n")
          puts list
          return
        end 

      end
    end

    register_sub_command lookup : Lookup, "Lookup Win32 projection data without writing files and print to a human friendly output"
  end
end