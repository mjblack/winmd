require "../spec_helper"
require "../../src/winmd"

module WinMD::Ecma335ImporterSpec
  describe "WinMD::Ecma335Importer" do
    it "imports local winmd metadata into WinMD::File models" do
      candidate_paths = [
        ::File.expand_path("../../winmd/Windows.Win32.winmd", __DIR__),   # winmd.cr/winmd
        ::File.expand_path("../../../winmd/Windows.Win32.winmd", __DIR__), # parent repo fixture
      ]
      winmd_path = candidate_paths.find { |path| ::File.exists?(path) }

      unless winmd_path
        puts "Skipping Ecma335Importer integration spec: run scripts/fetch-winmd.ps1 or place Windows.Win32.winmd in ./winmd"
        next
      end

      WinMD.top_level_namespace = "Win32cr"
      parsed = Ecma335.parse(winmd_path)
      importer = WinMD::Ecma335Importer.new(parsed)
      files = importer.import

      files.size.should be > 0
      files.any? { |f| f.functions.any? }.should be_true
      files.any? { |f| f.types.any? { |t| t.is_a?(WinMD::Type::Struct) || t.is_a?(WinMD::Type::Union) } }.should be_true
    end
  end
end
