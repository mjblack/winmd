# Runtime smoke test for freshly generated bindings.
#
# CI generates bindings into ./out (see .github/workflows/ci.yml) and then
# runs this program with `crystal run ci/smoke_generated.cr`. Unlike the
# --no-codegen checks, this links and executes the generated code, so it
# exercises @[Link] resolution, calling conventions, struct layout, enum
# values, GUID constants and COM vtable calls against the real Win32 API.
#
# Locally:
#   bin\winmd.exe generate --source-format winmd winmd\Windows.Win32.winmd out
#   crystal run ci\smoke_generated.cr
require "c/fileapi"
require "../out/src/macros"
require "../out/src/win32cr/foundation"
require "../out/src/win32cr/system/threading"
require "../out/src/win32cr/system/system_information"
require "../out/src/win32cr/system/pipes"
require "../out/src/win32cr/system/com"
require "../out/src/win32cr/system/registry"
require "../out/src/win32cr/ui/shell"

alias Fd = Win32cr::Foundation
alias SysCom = Win32cr::System::Com
alias SysReg = Win32cr::System::Registry

failures = 0
check = ->(name : String, ok : Bool) do
  puts "#{ok ? "ok  " : "FAIL"} #{name}"
  failures += 1 unless ok
end

# Null-terminated UTF-16 buffer for PWSTR parameters.
def wide(text : String) : Pointer(UInt16)
  text.to_utf16.to_unsafe
end

# Plain function taking a handle and returning an integer. (GetCurrentProcessId
# itself is declared by Crystal's LibC, so the generator comments it out.)
pid = Win32cr::System::Threading.getProcessId(LibC.GetCurrentProcess)
check.call("GetProcessId returns the current pid", pid == LibC.GetCurrentProcessId)

# Function filling a struct that contains a nested anonymous union.
info = uninitialized Win32cr::System::SystemInformation::SYSTEM_INFO
Win32cr::System::SystemInformation.getSystemInfo(pointerof(info))
check.call("GetSystemInfo reports processors", info.dwNumberOfProcessors > 0)
check.call("GetSystemInfo reports a page size", info.dwPageSize >= 4096)

# Enum-typed argument and a Flags enum value round trip.
check.call("THREAD_CREATION_FLAGS::CREATE_SUSPENDED value",
  Win32cr::System::Threading::THREAD_CREATION_FLAGS::THREAD_CREATE_SUSPENDED.value == 4_u32)

# Handles and buffers: anonymous pipe write/read through LibC.
read_side = Pointer(Void).null
write_side = Pointer(Void).null
created = Win32cr::System::Pipes.createPipe(pointerof(read_side), pointerof(write_side),
  Pointer(Win32cr::Security::SECURITY_ATTRIBUTES).null, 0_u32)
check.call("CreatePipe succeeds", created != 0)
if created != 0
  message = "generated bindings"
  written = 0_u32
  LibC.WriteFile(write_side, message.to_unsafe, message.bytesize, pointerof(written), nil)
  buffer = Bytes.new(64)
  read = 0_u32
  LibC.ReadFile(read_side, buffer.to_unsafe, buffer.size, pointerof(read), nil)
  check.call("pipe round trip", String.new(buffer[0, read]) == message)
  LibC.CloseHandle(read_side)
  LibC.CloseHandle(write_side)
end

# Typed error constants.
Fd.setLastErrorEx(Fd::WIN32_ERROR::ERROR_PATH_NOT_FOUND, 0_u32)
check.call("SetLastErrorEx/GetLastError", LibC.GetLastError == Fd::WIN32_ERROR::ERROR_PATH_NOT_FOUND.value)

# Registry: pointer typedef (HKEY), enum flags and an out-pointer to an enum.
hklm = Pointer(Void).new(SysReg::HKEY_LOCAL_MACHINE.to_i64.to_u64!)
size = 0_u32
hr = SysReg.regGetValueW(hklm, wide("HARDWARE\\DESCRIPTION\\System"), wide("Identifier"),
  SysReg::REG_ROUTINE_FLAGS::RRF_RT_ANY, Pointer(SysReg::REG_VALUE_TYPE).null, Pointer(Void).null, pointerof(size))
check.call("RegGetValueW size query", hr.value == 0 && size > 0)

# COM: initialization, GUID parsing, a coclass CLSID constant and vtable calls.
# dwCoInit is a plain UInt32 in the metadata (AssociatedEnum COINIT); COINIT is Int32-based.
hr = SysCom.coInitializeEx(Pointer(Void).null, SysCom::COINIT::COINIT_APARTMENTTHREADED.value.to_u32)
check.call("CoInitializeEx", hr == Fd::S_OK)

clsid = Win32cr::UI::Shell::CLSID_FileOpenDialog
check.call("CLSID_FileOpenDialog constant", clsid.data1 == 0xdc1c5a9c_u32)

malloc = Pointer(Void).null
SysCom.coGetMalloc(1_u32, pointerof(malloc))
imalloc = malloc.as(SysCom::IMalloc*)
block = imalloc.value.alloc(imalloc, 100_u64)
check.call("IMalloc.Alloc via vtable", !block.null?)
check.call("IMalloc.GetSize via vtable", imalloc.value.get_size(imalloc, block) == 100_u64)
imalloc.value.free(imalloc, block)
imalloc.value.release(imalloc)

dialog = Pointer(Void).null
hr = SysCom.coCreateInstance(pointerof(clsid), Pointer(Void).null,
  SysCom::CLSCTX::CLSCTX_INPROC_SERVER, pointerof(Win32cr::UI::Shell::IFileOpenDialog::GUID), pointerof(dialog))
check.call("CoCreateInstance(FileOpenDialog)", hr == Fd::S_OK && !dialog.null?)
unless dialog.null?
  unknown = dialog.as(SysCom::IUnknown*)
  unknown.value.release(unknown)
end
SysCom.coUninitialize

puts failures == 0 ? "all checks passed" : "#{failures} check(s) failed"
exit(failures == 0 ? 0 : 1)
