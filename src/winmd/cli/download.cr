module WinMD
  class CLI
    class Download < Admiral::Command
      define_help description: "WinMD Downloader"
      define_version WinMD::VERSION

      define_flag debug : Bool,
        description: "Debug",
        short: d,
        long: debug,
        required: false,
        default: false

      define_flag ref : String,
        description: "Git reference",
        short: r,
        long: ref,
        required: false

      define_argument source_url : String,
        description: "URL to JSON Repo",
        required: false # so if not provided we can display help. If required it wont be possible to display help

      define_argument dest_dir : String,
        description: "Where the downloads will reside",
        default: "work/win32json",
        required: false

      def run
        unless arguments.source_url
          puts help
          exit 1
        end

        url = begin
          if u = arguments.source_url
            URI.parse(u)
          else
            raise "Error: Missing source url"
          end
        rescue
          puts "Source URL is not a valid URL"
          puts help
          exit 1
        end

        git_repo = GitRepository.new(url)
        dest_dir = begin
          if d = arguments.dest_dir
            Path.windows(d)
          else
            puts "Error: Missing destination directory"
            puts help
            exit 1
          end
        end

        ref = begin
          if r = flags.ref
            r
          else
            "HEAD"
          end
        end

        unless Dir.exists?(dest_dir.parent)
          FileUtils.mkdir_p(dest_dir.parent)
        end
        git_repo.fetch_commit(ref, dest_dir)
      end
    end
    register_sub_command download : Download, "Download JSON repo containing Win32 API metadata"
  end
end
