module WinMD
  @[JSON::Serializable::Options(presence: true, emit_nulls: true)]
  class FunOverride
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    @@overrides = [] of FunOverride

    enum Type
      Function
      Enum
      Struct
    end

    @[JSON::Serializable::Options(presence: true, emit_nulls: true)]
    class Rule
      include JSON::Serializable
      include JSON::Serializable::Unmapped

      enum Type
        FunName          # Function Name
        FunAlias         # Function Alias (e.g. `fun alias_name = function_name)
        ReturnType       # Fun return type
        ParamName        # Parameter Name
        ParamType        # Parameter Data Type
        EnumName         # Enum Name
        EnumMemberName   # Enum Member Name
        EnumMemberValue  # Enum Integer Base Type
        StructName       # Struct Name
        StructFieldName  # Struct Field Name
        StructFieldType  # Struct Field Type
      end

      @[JSON::Field]
      property description : String # Rule description

      @[JSON::Field]
      property type : Type # Rule type

      @[JSON::Field]
      property index : Int32 = 0 # Index of the parameter to override

      @[JSON::Field]
      property key : String = "" # Key (if used)

      @[JSON::Field]
      property value : String # Value to override with

      def after_initialize
      end

      def type_name?
        @type == Type::Name
      end

      def type_alias?
        @type == Type::Alias
      end

      def param_name?
        @type == Type::ParamName
      end

      def param_type?
        @type == Type::ParamType
      end

      def enum_type?
        @type == Type::EnumType
      end

      def enum_value?
        @type == Type::EnumValue
      end

      def struct_field_name?
        @type == Type::StructFieldName
      end

      def struct_field_type?
        @type == Type::StructFieldType
      end
    end

    @[JSON::Field(ignore: false)]
    property name : String # Name of the function to override

    @[JSON::Field(ignore: false)]
    property namespace : String # Namespace of the function to override

    @[JSON::Field(ignore: false)]
    property type : Type # Data Type override applies to

    @[JSON::Field(ignore: false)] 
    property rule : Rule # The Rule

    def self.add_override(override : FunOverride)
      @@overrides << override
    end

    def self.overrides
      @@overrides
    end

    def self.load_overrides(file : Path)
      if ::File.exists?(file)
        begin
          json = JSON.parse(::File.read(file))
          json.as_a.each do |x|
            override = FunOverride.from_json(x.to_json)
            add_override(override)
            Log.debug { "Loaded override: #{override.name} : #{override.type} -> Rule type #{override.rule.type}" }
          end
        rescue e : JSON::SerializableError
          Log.fatal { "Failed to load overrides" }
          Log.fatal { e.message }
          exit 1
        end
      end
    end

    def self.find_ns_overrides(namespace : String) : Array(FunOverride)
      Log.debug { "Searching for overrides in namespace: #{namespace}" }
      resp = @@overrides.select { |x| x.namespace == namespace }
      Log.trace { "Overrides found: #{resp.inspect}"}
      Log.debug { "Total overrides found: #{resp.size}"}
      resp
    end

    def self.find_overrides(name : String, namespace : String, type : Type) : Array(FunOverride)
      Log.debug { "Searching for overrides: #{name} in #{namespace}" }
      resp = @@overrides.select { |x| x.name == name && x.namespace == namespace && x.type == type }
      Log.trace { "Overrides found: #{resp.inspect}"}
      Log.debug { "Total overrides found: #{resp.size}"}
      resp
    end

    delegate :type_name?, to: @rule
    delegate :type_alias?, to: @rule
    delegate :param_name?, to: @rule
    delegate :param_type?, to: @rule
  end
end
