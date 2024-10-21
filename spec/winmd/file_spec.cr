require "../spec_helper"
require "../../src/winmd"

module WinMD::Template::File
  describe "WinMD::Template::File" do
    json = ::File.read("./spec/fixtures/file.json")
    file = WinMD::File.from_json(json, "System.Com.json")

    describe "Constant type" do
      it "should have a constant named MARSHALINTERFACE_MIN" do
        file.constants.first.name.should eq("MARSHALINTERFACE_MIN")
      end

      it "constant MARSHALINTERFACE_MIN should have a value of \"500_u32\"" do
        file.constants.first.value.should eq("500_u32")
      end
    end

    describe "Enum type" do
      enum_type = file.types.select(WinMD::Type::Enum).first
      it "should have an enum named URI_CREATE_FLAGS" do
        enum_type.name.should eq("URI_CREATE_FLAGS")
      end

      it "enum shoulds have 18 members" do
        enum_type.members.size.should eq(18)
      end

      it "enum should be uint32 based" do
        enum_type.integer_base.should eq("UInt32")
      end
    end

    describe "COM Object" do
      com_type = file.types.select(WinMD::Type::Com).first
      it "should have the name IUnknown" do
        com_type.name.should eq("IUnknown")
      end

      it "should have a guid of 00000000-0000-0000-c000-000000000046" do
        com_type.guid.try &.should eq("00000000-0000-0000-c000-000000000046")
      end

      it "should have three methods" do
        com_type.methods.size.should eq(3)
      end

      it "first method should be query_interface" do
        com_type.methods[0].name.should eq("query_interface")
      end

      it "second method should be add_ref" do
        com_type.methods[1].name.should eq("add_ref")
      end

      it "third method should be release" do
        com_type.methods[2].name.should eq("release")
      end
    end

    describe "Function" do
      func = file.functions.first

      it "Function name should be GetErrorInfo" do
        func.name.should eq("GetErrorInfo")
      end

      it "should have two params" do
        func.params.size.should eq(2)
      end

      it "should have a return type of HRESULT" do
        func.return_type.as(WinMD::Type::ApiRef).name.should eq("HRESULT")
      end
    end
  end
end
