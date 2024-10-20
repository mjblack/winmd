class WinMD::Type::Com < WinMD::Type
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "Guid")]
  property guid : String | Nil

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "Methods")]
  property methods = [] of WinMD::Method

  @[JSON::Field(key: "Interface")]
  property interface : WinMD::Type | Nil

  @[JSON::Field(ignore: true)]
  property namespace : String = ""

  @[JSON::Field(ignore: true)]
  property resolved_methods = [] of WinMD::Method

  def after_initialize
    super
    # if /^_/.match(@name)
    #   @name += "_"
    # end
    @name = WinMD.fix_type_name(@name)
  end

  def get_guid
    if g = @guid
      begin
        new_guid = WinMD::Guid.new(g)
        return new_guid
      rescue
      end
    else
      begin
        new_guid = WinMD::Guid.new("00000000-0000-0000-0000-000000000000")
        return new_guid
      rescue
      end
    end
    nil
  end

  def resolve_methods
    if interf = @interface
      if file = WinMD.find_file_by_ns(interf.as(WinMD::Type::ApiRef).namespace)
        if com = file.find_com_interface(interf.as(WinMD::Type::ApiRef).name)
          new_methods = com.resolve_methods + @methods
          new_methods.each do |x|
            x.interface = @name
          end
          @resolved_methods = new_methods

          # look for duplicate methods and remediate
          @resolved_methods.each do |x|
            if (dup_methods = @resolved_methods.select { |m| m.name == x.name }).size > 1
              dup_methods.each_with_index do |v, index|
                i = index + 1
                new_name = "#{v.name}_#{i}"
                v.name = new_name
              end
            end
          end
        end
      end
    else
      @resolved_methods = @methods
    end
    return @resolved_methods
  end

  def file=(file : WinMD::File)
    super(file)
    if interface = @interface
      interface.file = file
    end
    @methods.each { |x| x.file = file }
  end

  def get_interface
    if interface = @interface
      return interface
    end
  end

  def render
    ECR.render "./src/winmd/ecr/com.ecr"
  end
end
