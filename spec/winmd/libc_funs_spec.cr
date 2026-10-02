require "../spec_helper"
require "../../src/winmd"

describe WinMD::LibCFuns do
  describe ".lib_c_directory_name" do
    it "drops the vendor component of a target triple" do
      WinMD::LibCFuns.lib_c_directory_name("x86_64-pc-windows-msvc").should eq("x86_64-windows-msvc")
      WinMD::LibCFuns.lib_c_directory_name("x86_64-unknown-linux-gnu").should eq("x86_64-linux-gnu")
      WinMD::LibCFuns.lib_c_directory_name("aarch64-apple-darwin").should eq("aarch64-darwin")
      WinMD::LibCFuns.lib_c_directory_name("wasm32-wasi").should eq("wasm32-wasi")
    end
  end

  describe ".discover" do
    it "lists the LibC functions of the installed Crystal for its default target" do
      names = WinMD::LibCFuns.discover
      names.size.should be > 200
      names.should eq(names.sort)
      names.should contain("GetLastError")
      names.should contain("CloseHandle")
      # Declared by stdlib files that a minimal program's prelude never
      # requires, so a `LibC.methods` macro would not list them. They still
      # collide with generated declarations once a program requires them.
      names.should contain("GetProcessHeap")
      names.should contain("RtlNtStatusToDosError")
    end

    it "fails clearly when the compiler cannot be run" do
      expect_raises(WinMD::LibCFuns::Error, /Could not run the Crystal compiler/) do
        WinMD::LibCFuns.discover("definitely-not-a-crystal-compiler")
      end
    end
  end

  describe ".load_list" do
    it "reads one name per line and ignores comments and blanks" do
      file = ::File.tempfile("libc_funs", ".txt") do |io|
        io.puts "# comment"
        io.puts "GetLastError"
        io.puts ""
        io.puts "  CloseHandle  "
      end
      begin
        WinMD::LibCFuns.load_list(Path.new(file.path)).should eq(["GetLastError", "CloseHandle"])
      ensure
        file.delete
      end
    end
  end
end
