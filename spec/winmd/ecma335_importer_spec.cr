require "../spec_helper"
require "../../src/winmd"

# Integration spec against the real Windows.Win32.winmd. The fixture is
# looked up from, in order: the WINMD_FIXTURE environment variable, winmd/ in
# this repo (`scripts/fetch-winmd.ps1` puts it there), and winmd/ in the
# parent directory (the sibling `ecma335` checkout). The specs are pending
# when none exists.
module WinMD::Ecma335ImporterSpec
  WINMD_CANDIDATES = [
    ENV["WINMD_FIXTURE"]?,
    ::File.expand_path("../../winmd/Windows.Win32.winmd", __DIR__),
    ::File.expand_path("../../../winmd/Windows.Win32.winmd", __DIR__),
  ].compact
  WINMD_PATH = WINMD_CANDIDATES.find { |path| ::File.exists?(path) } || WINMD_CANDIDATES[-2]

  private def self.load_importer : WinMD::Ecma335Importer
    WinMD.top_level_namespace = "Win32cr"
    WinMD.output_dir = Path.new("win32cr")
    WinMD.data_type_aliases_file = Path.new("examples/overrides/data_type_aliases.json")
    WinMD.fun_exceptions_file = Path.new("examples/overrides/fun_exceptions.json")
    WinMD.dll_exceptions_file = Path.new("examples/overrides/dll_exceptions.json")
    WinMD.init
    WinMD.files.clear
    importer = WinMD::Ecma335Importer.new(Ecma335.parse(WINMD_PATH))
    importer.import.each { |f| WinMD.add_file(f) }
    WinMD.resolve_com_interfaces
    importer
  end

  private def self.file_for(api : String) : WinMD::File
    WinMD.files.find { |f| f.api == api } || raise "no file for #{api}"
  end

  describe "WinMD::Ecma335Importer" do
    unless ::File.exists?(WINMD_PATH)
      pending "Run scripts/fetch-winmd.ps1 (or set WINMD_FIXTURE) to run the importer integration specs"
      next
    end

    importer = load_importer

    it "produces one file per API namespace, named like win32json" do
      importer.files.size.should be > 300
      importer.files.map(&.api).should contain("System.Threading")
      importer.files.map(&.api).should contain("Foundation")
      importer.files.map(&.api).should_not contain("Foundation.Metadata")
      importer.files.none? { |f| f.api == "Global" }.should be_true
      file_for("System.Threading").namespace.should eq("Win32cr::System::Threading")
    end

    it "imports functions with SetLastError, DllImport and parameters" do
      threading = file_for("System.Threading")
      create_thread = threading.functions.find { |f| f.name == "CreateThread" }.not_nil!
      create_thread.dll_import.should eq("kernel32")
      create_thread.set_last_error.should be_true
      create_thread.params.map(&.name).should eq(["lpThreadAttributes", "dwStackSize", "lpStartAddress", "lpParameter", "dwCreationFlags", "lpThreadId"])
      create_thread.return_type.as(WinMD::Type::ApiRef).name.should eq("HANDLE")
      create_thread.params[2].type.as(WinMD::Type::ApiRef).target_kind.should eq("FunctionPointer")
    end

    it "imports enums with numeric members, Flags and integer base" do
      threading = file_for("System.Threading")
      flags = threading.types.compact_map(&.as?(WinMD::Type::Enum)).find { |e| e.name == "THREAD_CREATION_FLAGS" }.not_nil!
      flags.flags.should be_true
      flags.integer_base.should eq("UInt32")
      flags.members.map(&.value).should eq(["0", "4", "65536"])
      flags.members.first.render.should eq("THREAD_CREATE_RUN_IMMEDIATELY = 0_u32")
    end

    it "imports constants including GUIDs, strings, floats and property keys" do
      threading = file_for("System.Threading")
      threading.constants.find { |c| c.name == "INFINITE" }.not_nil!.value.should eq("4294967295_u32")

      com = file_for("System.Com")
      guid = com.constants.find { |c| c.name == "CLSID_GlobalOptions" }.not_nil!
      guid.value.should start_with("LibC::GUID.new(")

      audio = file_for("Media.Audio")
      pkey = audio.constants.find { |c| c.name == "PKEY_AudioEndpoint_FormFactor" }.not_nil!
      pkey.value.should start_with("Win32cr::Foundation::PROPERTYKEY.new(LibC::GUID.new(")

      d3d11 = file_for("Graphics.Direct3D11")
      d3d11.constants.find { |c| c.name == "D3D11_FLOAT32_MAX" }.not_nil!.value.should eq("3.4028235e+38")

      msi = file_for("System.ApplicationInstallationAndServicing")
      msi.constants.find { |c| c.name == "INSTALLPROPERTY_PACKAGENAME" }.not_nil!.value.should eq("\"PackageName\"")
    end

    it "imports native typedefs, delegates and COM interfaces" do
      foundation = file_for("Foundation")
      typedefs = foundation.types.compact_map(&.as?(WinMD::Type::NativeTypedef))
      bstr = typedefs.find { |t| t.name == "BSTR" }.not_nil!
      bstr.free_func.should eq("SysFreeString")
      bstr.def_.should be_a(WinMD::Type::PointerTo)
      handle = typedefs.find { |t| t.name == "HANDLE" }.not_nil!
      handle.invalid_handle_value.should eq(-1)

      threading = file_for("System.Threading")
      start_routine = threading.types.compact_map(&.as?(WinMD::Type::FunctionPointer)).find { |t| t.name == "LPTHREAD_START_ROUTINE" }.not_nil!
      start_routine.params.size.should eq(1)
      start_routine.return_type.as(WinMD::Type::Native).name.should eq("UInt32")

      com = file_for("System.Com")
      iunknown = com.find_com_interface("IUnknown").not_nil!
      iunknown.guid.should eq("00000000-0000-0000-c000-000000000046")
      iunknown.methods.map(&.name).should eq(["query_interface", "add_ref", "release"])
      iunknown.interface.should be_nil
      idispatch = com.find_com_interface("IDispatch").not_nil!
      idispatch.interface.as(WinMD::Type::ApiRef).name.should eq("IUnknown")
      idispatch.resolve_methods.size.should eq(7)
    end

    it "imports structs and unions with nested types, layout and architectures" do
      kernel = file_for("System.Kernel")
      headers = kernel.types.compact_map(&.as?(WinMD::Type::Struct)).select { |s| s.name == "SLIST_HEADER" }
      headers.size.should be > 1
      headers.all?(&.is_union?).should be_true
      headers.all? { |h| h.architectures.any? }.should be_true
      headers.first.nested_types.size.should be > 0

      foundation = file_for("Foundation")
      point = foundation.types.compact_map(&.as?(WinMD::Type::Struct)).find { |s| s.name == "POINT" }.not_nil!
      point.fields.map(&.name).should eq(["x", "y"])
      point.fields.first.type.as(WinMD::Type::Native).name.should eq("Int32")
    end

    it "renders a namespace that the Crystal compiler accepts" do
      out_dir = Path.new(Dir.tempdir).join("winmd_importer_spec_#{Process.pid}")
      begin
        WinMD.write_files(out_dir)
        foundation = out_dir.join("src", "win32cr", "foundation.cr")
        ::File.exists?(foundation).should be_true
        output = IO::Memory.new
        # winmd_spec.cr points CRYSTAL_PATH at ./src for its own purposes; the
        # child compiler must not inherit that or it cannot find the prelude.
        env = {"CRYSTAL_PATH" => nil}
        status = Process.run("crystal", ["build", "--no-codegen", foundation.to_s], env: env, output: output, error: output)
        status.success?.should be_true, output.to_s
      ensure
        FileUtils.rm_rf(out_dir)
      end
    end
  end
end
