# winmd

Win32 API metadata bindings generator.

The generator supports:
- JSON metadata input (win32json-style)
- Native `.winmd` input via [`ecma335`](https://github.com/mjblack/ecma335)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     winmd:
       github: mjblack/winmd
   ```

2. Run `shards install`

## Usage

Run the command `bin\winmd.exe` from the shard itself or from your own shard.

Examples:

```bash
# Existing JSON-based flow
bin/winmd generate ./path/to/json ./out

# Native WinMD flow
bin/winmd generate --source-format winmd ./winmd/Windows.Win32.winmd ./out
```

Both flows read the optional override files (`data_type_aliases.json`,
`dll_exceptions.json`, `fun_exceptions.json`, `overrides.json`) from the
current directory, so run the generator from the directory that holds them.
Examples live in `examples/overrides`.

### WinMD input

With `--source-format winmd` the metadata is parsed by the
[`ecma335`](https://github.com/mjblack/ecma335) shard and converted, namespace by namespace, into
the same document shape that win32json produces. Everything downstream
(templates, overrides, aliases) is shared with the JSON flow, so the output is
laid out and named identically. Constants, enums, structs, unions (with nested
types and per-architecture variants), native typedefs, function pointers, COM
interfaces and functions are all imported.

Extra flags for this mode:

- `--dump-json DIR` writes the intermediate `<Api>.json` documents to `DIR`.
  They are useful for diffing against real win32json output or for debugging
  a conversion.
- `--associated-enums` types integer parameters and struct fields that carry
  an `AssociatedEnum` attribute as that enum. Current metadata declares these
  as plain integers; the flag reproduces the enum-typed signatures that older
  metadata (and win32json builds based on it) had.

GUID-valued constants are emitted as `LibC::GUID` values, and `PROPERTYKEY` /
`DEVPROPKEY` constants as struct values, in addition to what the JSON flow
produces. Constants typed by a pointer typedef (`HKEY_LOCAL_MACHINE`,
`INVALID_HANDLE_VALUE`, `HWND_BROADCAST`, ...) are emitted as typed pointers,
e.g. `HKEY.new(0xffffffff80000002_u64)`, matching the casts in the C headers.

## Development

Build the CLI:

```bash
shards install --skip-postinstall
shards build
```

Run the specs:

```bash
crystal spec
```

The importer integration specs need `Windows.Win32.winmd`. Fetch the version
pinned in `winmd.version` into `winmd/` (or point `WINMD_FIXTURE` at a copy):

```bash
pwsh ./scripts/fetch-winmd.ps1
```

CI (`.github/workflows/ci.yml`) runs the specs on Windows and then
generates bindings from the pinned metadata and compiles a set of
representative namespaces.

## Contributing

1. Fork it (<https://github.com/mjblack/winmd/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Matthew J. Black](https://github.com/mjblack) - creator and maintainer
