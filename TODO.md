# path-manager - Home Manager Module

A Home Manager module for declarative path management in impermanent NixOS setups.

## Status

✅ **Core functionality complete** - All 4 path states implemented and tested (5/5 tests passing)

## Library Functions

The `lib/default.nix` provides convenient helper functions for declaring path states:

### `mkImmutablePath { source?, text? }`
Creates an immutable path managed by home-manager. The file is recreated from source/text on each activation.

```nix
home.pathManager = {
  ".bashrc" = pathManagerLib.mkImmutablePath { text = "echo hello"; };
  ".vimrc" = pathManagerLib.mkImmutablePath { source = ./vimrc; };
};
```

### `mkMutablePath`
Creates a mutable path that persists across reboots with no initial content.

```nix
home.pathManager = {
  ".local/state/database.db" = pathManagerLib.mkMutablePath;
};
```

### `mkEphemeralPath`
Creates an ephemeral path that lives in tmpfs and is wiped on each reboot.

```nix
home.pathManager = {
  ".cache/downloads" = pathManagerLib.mkEphemeralPath;
};
```

### `mkExtensiblePath { source?, text? }`
Creates a persisted file with initial content. After creation, the file can be modified freely.

```nix
home.pathManager = {
  ".config/app/config.toml" = pathManagerLib.mkExtensiblePath {
    text = ''
      [settings]
      theme = "dark"
    '';
  };
};
```

## Implementation Status

### 1. Core Module Functionality (TDD)

#### 1.1. Scenario: `immutable` (Read-only)
- ✅ Write test for `immutable` state
- ✅ Implement `immutable` state logic
- ✅ Tests pass (uses `lib.mkForce` for precedence)

#### 1.2. Scenario: `ephemeral` (Temporary)
- ✅ Write test for `ephemeral` state
- ✅ Implement `ephemeral` state logic
- ✅ Tests pass

#### 1.3. Scenario: `mutable` (Persistent)
- ✅ Write test for `mutable` state
- ✅ Implement `mutable` state logic
- ✅ Tests pass (fixed: use conditional expressions instead of `lib.mkIf`)

#### 1.4. Scenario: `extensible` (Persistent with Initial Content)
- ✅ Write tests for `extensible` state (2 tests: persistence + tmpfiles rule)
- ✅ Implement `extensible` state logic (Linux `systemd.tmpfiles.rules`)
- ✅ Tests pass on Linux

### 2. Library Functions
- ✅ Create `lib/default.nix` with helper functions
- ✅ Export lib from `flake.nix`
- ✅ Update tests to use library functions

## Remaining Work

### Cross-Platform Support (`nix-darwin`)
- [ ] Implement `extensible` state logic for `nix-darwin` using `launchd`
- [ ] Write specific tests for `nix-darwin` `extensible` state
- [ ] Run tests on `nix-darwin` and confirm tests pass

### Comprehensive Testing
- [ ] Configure `checkmate` to run tests for all compatible systems (`--all-systems`)
- [ ] Add more edge case tests for all scenarios
- [ ] Test with real impermanence module integration
- [ ] Test against different persistence methods:
  - [ ] Symlinks (default)
  - [ ] Bind mounts (`home.persistence.<path>.allowOther = true`)
  - [ ] FUSE/bindfs if supported by impermanence

### Documentation and Cleanup
- ✅ Document library functions in TODO.md
- [ ] Add comprehensive inline documentation to `path-manager.nix`
- [ ] Add README.md with usage examples
- [ ] Add example flake for integration
- [ ] Ensure all code adheres to Nix best practices and style guides
- [ ] Prepare for potential PR to `impermanence` project

## Usage

To use this module in your configuration:

```nix
{
  inputs = {
    path-manager.url = "github:youruser/path-manager-module-checkmate";
    # ... other inputs
  };

  outputs = { home-manager, path-manager, ... }: {
    homeConfigurations.youruser = home-manager.lib.homeManagerConfiguration {
      modules = [
        path-manager.flakeModule
        {
          home.pathManager = with path-manager.lib; {
            ".config/chromium/Default" = mkMutablePath;
            ".bashrc" = mkImmutablePath { source = ./bashrc; };
            ".cache" = mkEphemeralPath;
          };
        }
      ];
    };
  };
}
```

## Architecture Notes

### Precedence Handling
The module uses `lib.mkForce` on individual paths for the `immutable` state to ensure `pathManager` takes precedence over conflicting declarations from `home.file`, `home.impermanence`, and `environment.impermanence`.

### Testing Strategy
Uses checkmate (vic/checkmate) with nix-unit for TDD. Tests verify:
1. Immutable paths are added to `home.file`
2. Ephemeral paths are NOT added to `home.file` or persistence
3. Mutable paths are added to `home.persistence.<path>.files`
4. Extensible paths are added to both `home.persistence.<path>.files` AND `systemd.tmpfiles.rules`
