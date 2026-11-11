require "../spec_helper"
require "../../src/winmd"

private def parse(source : String, require_path = "c/test")
  WinMD::LibCFuns.parse_source(source, require_path)
end

private def signature(source : String, name : String)
  parse(source).find { |s| s.name == name }.not_nil!
end

describe WinMD::LibCFuns do
  describe ".lib_c_directory_name" do
    it "drops the vendor component of a target triple" do
      WinMD::LibCFuns.lib_c_directory_name("x86_64-pc-windows-msvc").should eq("x86_64-windows-msvc")
      WinMD::LibCFuns.lib_c_directory_name("x86_64-unknown-linux-gnu").should eq("x86_64-linux-gnu")
      WinMD::LibCFuns.lib_c_directory_name("aarch64-apple-darwin").should eq("aarch64-darwin")
      WinMD::LibCFuns.lib_c_directory_name("wasm32-wasi").should eq("wasm32-wasi")
    end
  end

  describe ".parse_source" do
    it "spells lib types absolutely and Crystal primitives bare" do
      sig = signature(<<-CR, "GetFileTime")
        lib LibC
          alias DWORD = UInt32
          fun GetFileTime(hFile : HANDLE, lpCreationTime : FILETIME*, flags : DWORD, count : Int32, raw : Void*) : BOOL
        end
        CR
      sig.lib_name.should eq("LibC")
      sig.real_name.should eq("GetFileTime")
      sig.require_path.should eq("c/test")
      sig.params.not_nil!.map(&.type).should eq([
        "::LibC::HANDLE", "Pointer(::LibC::FILETIME)", "::LibC::DWORD", "Int32", "Pointer(Void)",
      ])
      sig.params.not_nil!.map(&.name).should eq(["hFile", "lpCreationTime", "flags", "count", "raw"])
      sig.return_type.should eq("::LibC::BOOL")
    end

    it "renders nested pointers, procs, static arrays and qualified names as values" do
      sig = signature(<<-CR, "Odd")
        lib LibNTDLL
          fun Odd(a : HKEY**, b : (Void*, DWORD) -> BOOL, c : UInt8[16], d : LibC::ULONG, e : ::Int32, f : -> ) : Void*
        end
        CR
      sig.lib_name.should eq("LibNTDLL")
      sig.params.not_nil!.map(&.type).should eq([
        "Pointer(Pointer(::LibNTDLL::HKEY))",
        "Proc(Pointer(Void), ::LibNTDLL::DWORD, ::LibNTDLL::BOOL)",
        "StaticArray(UInt8, 16)",
        "::LibC::ULONG",
        "Int32",
        "Proc(Nil)",
      ])
      sig.return_type.should eq("Pointer(Void)")
    end

    it "keeps the C symbol, varargs and a missing return type" do
      sigs = parse(<<-CR)
        lib LibC
          fun RtlGenRandom = SystemFunction036(buffer : Void*, length : ULong) : BOOLEAN
          fun printf(format : Char*, ...) : Int
          fun GetSystemTimeAsFileTime(time : FILETIME*)
        end
        CR
      random = sigs.find { |s| s.name == "RtlGenRandom" }.not_nil!
      random.real_name.should eq("SystemFunction036")
      sigs.find { |s| s.name == "printf" }.not_nil!.varargs.should be_true
      sigs.find { |s| s.name == "GetSystemTimeAsFileTime" }.not_nil!.return_type.should eq("Void")
    end

    it "parses declarations inside macro conditionals" do
      sigs = parse(<<-CR)
        lib LibC
          fun GetCurrentThread : HANDLE
          {% if LibC::WIN32_WINNT >= LibC::WIN32_WINNT_WIN8 %}
            fun GetCurrentThreadStackLimits(lowLimit : ULONG_PTR*, highLimit : ULONG_PTR*) : Void
          {% else %}
            fun Older : Int32
          {% end %}
        end
        CR
      limits = sigs.find { |s| s.name == "GetCurrentThreadStackLimits" }.not_nil!
      limits.params.not_nil!.map(&.type).should eq(["Pointer(::LibC::ULONG_PTR)", "Pointer(::LibC::ULONG_PTR)"])
      sigs.map(&.name).should contain("Older")
    end

    it "falls back to names only when a declaration cannot be parsed" do
      sigs = parse(<<-CR)
        lib LibC
          {% for name in %w(GetA GetB) %}
            fun {{name.id}} : Int32
          {% end %}
          fun Plain : Int32
        end
        CR
      sigs.map(&.name).should contain("Plain")
      sigs.find { |s| s.name == "Plain" }.not_nil!.params.should eq([] of WinMD::LibCFuns::Param)
    end

    it "reports top-level funs by name only and survives a syntax error" do
      # A top-level `fun` defines a C-callable Crystal function; the textual
      # scan cannot tell it apart, so the name is kept (and not redeclared)
      # but no wrapper can forward to it.
      top_level = parse("fun not_in_lib : Int32")
      top_level.map(&.name).should eq(["not_in_lib"])
      top_level.first.params.should be_nil
      sigs = parse(<<-CR)
        lib LibC
          fun Broken(a : ) : Int32
          fun Fine : Int32
        end
        CR
      broken = sigs.find { |s| s.name == "Broken" }.not_nil!
      broken.params.should be_nil
      sigs.map(&.name).should contain("Fine")
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

  describe ".discover_signatures" do
    it "returns full declarations keyed by C symbol, with the file to require" do
      sigs = WinMD::LibCFuns.discover_signatures
      heap = sigs["GetProcessHeap"]
      heap.lib_name.should eq("LibC")
      heap.return_type.should eq("::LibC::HANDLE")
      heap.params.should eq([] of WinMD::LibCFuns::Param)
      heap.require_path.should eq("c/heapapi")

      alloc = sigs["HeapAlloc"]
      alloc.params.not_nil!.map(&.type).should eq(["::LibC::HANDLE", "::LibC::DWORD", "::LibC::SizeT"])
      alloc.return_type.should eq("Pointer(Void)")

      # Declared in a lib other than LibC; the wrapper has to call that lib.
      sigs["RtlNtStatusToDosError"].lib_name.should eq("LibNTDLL")
      # Keyed by the C name, not the Crystal-side alias.
      sigs.has_key?("SystemFunction036").should be_true
      sigs.has_key?("RtlGenRandom").should be_false
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

describe WinMD::Function do
  describe ".value_type" do
    it "rewrites pointer suffixes into Pointer(...) so the type can be passed as a value" do
      WinMD::Function.value_type("Win32cr::Foundation::HANDLE").should eq("Win32cr::Foundation::HANDLE")
      WinMD::Function.value_type("Void*").should eq("Pointer(Void)")
      WinMD::Function.value_type("UInt16**").should eq("Pointer(Pointer(UInt16))")
    end
  end
end
