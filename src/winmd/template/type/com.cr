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

  # The full vtable: inherited methods first, then this interface's own.
  #
  # Every method is copied before it is renamed, so de-duplicating overloads
  # (COM allows the same name at several inheritance levels) never leaks into
  # the base interface or into other interfaces that share the same base. The
  # result is memoized because rendering asks for it several times.
  # The full vtable: inherited methods first, then this interface's own.
  #
  # Every method is copied before it is renamed, so de-duplicating overloads
  # (COM allows the same name at several inheritance levels) never leaks into
  # the base interface or into other interfaces that share the same base. The
  # result is memoized because rendering asks for it several times.
  def resolve_methods
    return @resolved_methods unless @resolved_methods.empty?

    inherited = [] of WinMD::Method
    if base = base_interface_ref
      if file = WinMD.find_file_by_ns(base.namespace)
        if com = file.find_com_interface(base.name)
          inherited = com.resolve_methods
        end
      end
    end

    merged = (inherited + @methods).map(&.dup)
    merged.each { |x| x.interface = @name }

    # Overloads get a 1-based suffix in vtable order: foo_1, foo_2, ...
    # Grouping is by the original metadata name so that overloads already
    # suffixed at a base level line up with the ones added here.
    counts = merged.group_by(&.original_name).transform_values(&.size)
    seen = Hash(String, Int32).new(0)
    merged.each do |x|
      if counts[x.original_name] > 1
        seen[x.original_name] += 1
        x.name = "#{x.original_name}_#{seen[x.original_name]}"
      else
        x.name = x.original_name
      end
    end

    @resolved_methods = merged
  end

  # The base interface reference, given directly or wrapped in a pointer.
  private def base_interface_ref : WinMD::Type::ApiRef?
    case interf = @interface
    when WinMD::Type::ApiRef   then interf
    when WinMD::Type::PointerTo then interf.child.as?(WinMD::Type::ApiRef)
    else                            nil
    end
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
