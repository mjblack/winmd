require "../spec_helper"
require "../../src/winmd"

module WinMD::Template::Include
  # Include files are basic.
  describe "WinMD Template Include" do
    api = "Win32.System.Test"
    file = WinMD::File.from_json("{}", "Win32.System.File.json")
    include_type = WinMD::Include.new(api, file)

    it "should have path of win32/system" do
      include_type.path.should eq("win32/system")
    end

    it "should have the qualified path of ./test.cr" do
      include_type.qualified_path.should eq("./test.cr")
    end
  end
end
