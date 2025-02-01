class WinMD::Type::Struct < WinMD::Type
  include WinMD::Architecture

  @[JSON::Field(key: "Name")]
  property name : String

  @[JSON::Field(key: "Architectures")]
  property architectures = [] of String

  @[JSON::Field(key: "Platform")]
  property platform : String | Nil

  @[JSON::Field(key: "Size")]
  property size : Int32

  @[JSON::Field(key: "PackingSize")]
  property packing_size : Int32

  @[JSON::Field(key: "Fields")]
  property fields = [] of WinMD::Type::Struct::StructField

  @[JSON::Field(key: "Attrs")]
  property attrs = [] of String

  @[JSON::Field(key: "NestedTypes")]
  property nested_types = [] of WinMD::Type

  @[JSON::Field(key: "Comment")]
  property comment : String?

  @[JSON::Field(key: "Union", ignore_deserialize: true)]
  property union : Bool = false

  @[JSON::Field(key: "Namespace", ignore_deserialize: true)]
  property namespace : String = ""

  @[JSON::Field(key: "MDParent", ignore_deserialize: true)]
  property parent : Struct?

  @[JSON::Field(ignore: true)]
  property override_name : String = ""

  def render
    fix_pad_size
    ECR.render "./src/winmd/ecr/struct.ecr"
  end

  def fix_pad_size
    @nested_types.each do |t|
      t.as(WinMD::Type::Struct).pad_size = @pad_size + 2
      t.as(WinMD::Type::Struct).fix_pad_size
    end

    @fields.each do |f|
      f.pad_size = @pad_size + 2
    end
  end

  def is_union?
    @union
  end

  # Check for dup field name so it can be renamed
  protected def check_field_dup(field_name : String)
    if @fields.count { |x| x.name == field_name } > 1
      true
    else
      false
    end
  end

  def file=(file : WinMD::File)
    super(file)
    if const = file.constants.find { |x| x.name == @name }
      const.name += "_"
    end
    @fields.each do |f|
      f.file = file
      if fields_dup = @fields.select { |x| x.name == f.name }

        # We want to skip the first entry since it is the first
        fields_dup[1..-1].each do |x|
          name = x.name
          loop do
            if check_field_dup(name)
              name = name + "_"
            else
              break
            end
          end
          x.name = name
        end
      end
    end
    @nested_types.each do |n|
      n.file = file
      n.as(WinMD::Type::Struct).namespace = @namespace + "::" + @name
      n.nested_type = true
      n.as(WinMD::Type::Struct).parent = self
      # TODO: Do we really need to loop through all??
      @fields.find do |field|
        if field.type.is_a?(WinMD::Type::ApiRef) && field.type.as(WinMD::Type::ApiRef).name == n.as(WinMD::Type::Struct).name
          field.type.nested_type = true
        end
        if field.type.is_a?(WinMD::Type::Array) && field.type.as(WinMD::Type::Array).child.is_a?(WinMD::Type::ApiRef) &&
            field.type.as(WinMD::Type::Array).child.as(WinMD::Type::ApiRef).name == n.as(WinMD::Type::Struct).name
          field.type.nested_type = true
        end
        if field.type.is_a?(WinMD::Type::PointerTo) && field.type.as(WinMD::Type::PointerTo).child.is_a?(WinMD::Type::ApiRef) &&
            field.type.as(WinMD::Type::PointerTo).child.as(WinMD::Type::ApiRef).name == n.as(WinMD::Type::Struct).name
          field.type.nested_type = true
        end
      end
    end
  end

  def after_initialize
    @name = WinMD.fix_type_name(@name)
  end

  def apply_overrides
    overrides = WinMD::FunOverride.find_overrides(@name, @file.not_nil!.namespace, WinMD::FunOverride::Type::Struct)
    apply_overrides(overrides)
    @nested_types.each(&.apply_overrides)
  end

  def apply_overrides(overrides : Array(WinMD::FunOverride))
    overrides.each do |override|
      case override.rule.type
      when WinMD::FunOverride::Rule::Type::StructName
        Log.debug { "Applying name override for #{@name} -> #{override.rule.value}" }
        @override_name = override.rule.value
      when WinMD::FunOverride::Rule::Type::StructFieldName
        Log.debug { "Applying struct field name override for #{@name} -> #{override.rule.value}" }
        @fields[override.rule.index].name = override.rule.value
      when WinMD::FunOverride::Rule::Type::StructFieldType
        Log.debug { "Applying struct field type override for #{@name} -> #{override.rule.value}" }
        @fields[override.rule.index].override_type = override.rule.value
      end
    end
  end
end
