class WinMD::Include

  # Filename of the single consolidated file that holds placeholder aliases
  # for foreign (non-`Windows.Win32`) namespaces. Lives at the lib root.
  EXTERNAL_REFS_FILENAME = "external_refs.cr"

  getter api : String
  getter filename : String
  getter path : String = ""
  getter file : WinMD::File
  getter same_file : Bool = false


  # api will be a string like "System.Com"
  # tfile is the current TFile being processed.
  def initialize(@api : String, @file : WinMD::File)
    if foreign?
      # Foreign WinRT refs all route through one consolidated file at the
      # lib root rather than per-namespace placeholder shells.
      @path = ""
      @filename = EXTERNAL_REFS_FILENAME
      return
    end

    new_api_path = @api.underscore
    api_path_parts = new_api_path.split(".")
    if api_path_parts.size > 1
      @path = ::File.dirname(new_api_path.gsub(".", "/"))
    else
      @path = ""
    end
    @filename = api_path_parts.last
    if /\.json$/.match(@filename)
      @filename = @filename.gsub("\.json", "\.cr")
    end
    unless /\.cr$/.match(@filename)
      @filename += ".cr"
    end
  end

  # True if the included api lives outside the projected Win32 namespace
  # tree. The importer remaps foreign WinRT namespaces (`Windows.Foundation`
  # etc.) onto a `WinRT.*` prefix, so api refs that survived projection
  # with that marker are the ones to consolidate.
  def foreign?
    @api.starts_with?("WinRT.")
  end

  def ==(other : String)
    @api == other
  end

  def ==(other : Include)
    # Foreign includes all resolve to the same physical file, so collapse
    # them into a single require regardless of which WinRT namespace they
    # came from.
    return true if foreign? && other.foreign?
    @api == other.api
  end

  def qualified_path
    inc_path = Path.posix("./").join(Path.posix(@path).join(Path.posix(@filename)).relative_to(Path.posix(@file.rel_path))).to_s
    inc_path
  end

  def render
    ECR.render "./src/winmd/ecr/include.ecr"
  end

  def resolve_path
    if @path == @file.rel_path && @filename == @file.file_name
      @same_file = true
    end
  end
end