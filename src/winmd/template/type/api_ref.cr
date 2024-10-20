class WinMD::Type::ApiRef < WinMD::Type

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "TargetKind")]
  property target_kind : String

  @[JSON::Field(key: "Api")]
  property api : String

  @[JSON::Field(key: "Parents")]
  property parents = [] of String

  @[JSON::Field(ignore: true)]
  getter namespace : String = ""

  @[JSON::Field(ignore: true)]
  property namespace_path : String = ""

  def after_initialize
    super
    @name = WinMD.fix_type_name(@name)
    set_namespace(@api)
  end

  def file=(file : File)
    @file = file
    inc = WinMD::Include.new(@api, file)
    file.add_include(inc)
  end

  def set_namespace(name : String)
    @namespace, @namespace_path = WinMD.fix_namespace(name)
  end

  def resolved_name
    if @nested_type
      return @name
    end
    if target_kind == "Com"
      return "Void*"
    end
    if @file.nil?
      file = WinMD.find_file_by_ns(@namespace)
      @file = file
    end
    if f = @file
      if WinMD.fix_namespace(@api) == f.namespace
        return @name
      else
        fqdn_name = @namespace + "::" + @name
        return fqdn_name
      end
    else
      return @name
    end
  end

  def render
    ECR.render "./src/winmd/ecr/api_ref.ecr"
  end
end