class WinMD::Include

  getter api : String
  getter filename : String
  getter path : String = ""
  getter file : WinMD::File
  getter same_file : Bool = false


  # api will be a string like "System.Com"
  # tfile is the current TFile being processed.
  def initialize(@api : String, @file : WinMD::File)
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

  def ==(other : String)
    @api == other
  end

  def ==(other : Include)
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