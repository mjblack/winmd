# winmd

Win32 API metadata bindings generator.

The generator supports:

- JSON metadata input (win32json-style)
- Native `.winmd` input via [`ecma335`](../README.md)

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

Fetch `Windows.Win32.winmd` (uses the version pinned in `winmd.version`):

```bash
pwsh ./scripts/fetch-winmd.ps1
```

Override the version or output path:

```bash
pwsh ./scripts/fetch-winmd.ps1 -Version 70.0.11-preview
pwsh ./scripts/fetch-winmd.ps1 -OutputPath winmd/Windows.Win32.winmd
```

Examples:

```bash
# Existing JSON-based flow
bin/winmd generate ./path/to/json ./out

# Native WinMD flow (new)
bin/winmd generate --source-format winmd ./winmd/Windows.Win32.winmd ./out
```

## Contributing

1. Fork it (<https://github.com/mjblack/winmd/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Matthew J. Black](https://github.com/mjblack) - creator and maintainer
