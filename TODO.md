# path-manager - Path Management for NixOS + Impermanence

A dual-module system for declarative path management in impermanent NixOS setups.

## Status

✅ **Feature Complete** - Dual module architecture with full conflict detection (10/10 tests passing)

## Architecture Overview

path-manager provides **two complementary modules**:

### 1. Home Manager Module (Universal)
- Works on **any platform** (NixOS, nix-darwin, standalone HM)
- Provides 4 path states: immutable, ephemeral, mutable, extensible
- Best-effort precedence using `lib.mkForce`
- ⚠️ **Limited validation** - cannot detect all conflicts due to HM module system limitations

### 2. NixOS Module (NixOS + Impermanence)
- **NixOS-only** with full system-level view
- Detects conflicts between `pathManager`, `home.file`, and `home.persistence`
- Provides detailed error messages with corrective guidance
- Recommended for NixOS + impermanence setups

**Note**: nix-darwin support not needed - impermanence is Linux-only

## The Path State Matrix

Each state maps to a combination of `home.file` and `home.persistence`:

| State | home.file | home.persistence | tmpfiles | Use Case |
|-------|-----------|------------------|----------|----------|
| `immutable` | ✅ YES | ❌ NO | ❌ | Config-managed, recreated each activation |
| `ephemeral` | ❌ NO | ❌ NO | ❌ | Temporary, wiped on reboot |
| `mutable` | ❌ NO | ✅ YES | ❌ | User data, persisted, not managed |
| `extensible` | ❌ NO | ✅ YES | ✅ | Initialized once, then mutable |

## Library Functions

The `lib/default.nix` provides convenient helper functions:

### `mkImmutablePath { source?, text? }`
HM-managed file recreated on each activation.

```nix
".bashrc" = mkImmutablePath { text = "echo hello"; };
".vimrc" = mkImmutablePath { source = ./vimrc; };
```

### `mkMutablePath`
Persisted file with no initial content.

```nix
".local/state/database.db" = mkMutablePath;
```

### `mkEphemeralPath`
Temporary file wiped on reboot.

```nix
".cache/downloads" = mkEphemeralPath;
```

### `mkExtensiblePath { source?, text? }`
Persisted file with initial content, then freely editable.

```nix
".config/app/config.toml" = mkExtensiblePath {
  text = ''
    [settings]
    theme = "dark"
  '';
};
```

## Usage

### On NixOS (Recommended - Full Validation)

```nix
{
  inputs.path-manager.url = "github:youruser/path-manager-module-checkmate";

  outputs = { nixpkgs, path-manager, home-manager, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        home-manager.nixosModules.home-manager
        path-manager.nixosModules.path-manager
        {
          pathManager.enable = true;
          pathManager.users.alice = with path-manager.lib; {
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

### Standalone Home Manager (Best Effort)

```nix
{
  inputs.path-manager.url = "github:youruser/path-manager-module-checkmate";

  outputs = { path-manager, home-manager, ... }: {
    homeConfigurations.alice = home-manager.lib.homeManagerConfiguration {
      modules = [
        path-manager.homeManagerModules.path-manager
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

## Implementation Status

### ✅ Completed

#### Core Functionality
- [x] All 4 path states (immutable, ephemeral, mutable, extensible)
- [x] Library helper functions
- [x] Precedence logic with `lib.mkForce`
- [x] 10/10 tests passing with checkmate

#### HM Module
- [x] Works on all platforms
- [x] Integrates with impermanence when available
- [x] systemd.tmpfiles for extensible state
- [x] Documented limitations

#### NixOS Module
- [x] System-level conflict detection
- [x] Validates against home.file and home.persistence
- [x] Detailed error messages
- [x] Per-user configuration

#### Testing & Validation
- [x] TDD with checkmate/nix-unit
- [x] Tests for all 4 states
- [x] Precedence tests (immutable overrides)
- [x] Persistence tests (mutable/extensible)

#### Documentation
- [x] Library function docs
- [x] Usage examples
- [x] Architecture notes
- [x] Module comparison

### 📋 Remaining Work

#### Testing
- [ ] Test with real NixOS + impermanence integration
- [ ] Test against bind mounts (vs symlinks)
- [ ] Edge case tests

#### Documentation
- [ ] Add README.md
- [ ] Example flake repository
- [ ] Inline documentation improvements
- [ ] Video/blog post?

#### Future Enhancements
- [ ] Support for `environment.persistence` (system-level)
- [ ] Darwin-specific extensible implementation (if impermanence adds macOS support)
- [ ] Validation tool: `nix run .#path-manager-check`

## Architecture Notes

### Why Two Modules?

**HM Module Limitations:**
- Operates within Home Manager's module system
- By evaluation time, all `home.file` contributions have merged
- Cannot distinguish "user declared" vs "other module declared"
- Limited conflict detection possible

**NixOS Module Advantages:**
- Operates at system level before HM evaluation
- Can see `config.home-manager.users.<user>.*` as a whole
- Detects conflicts before they cause issues
- Provides actionable error messages

### Precedence Strategy

**For immutable paths:**
- Uses `lib.mkForce` to override conflicting `home.file` declarations
- Allows intentional override pattern

**For other states:**
- Should NOT conflict with `home.file` (configuration error)
- NixOS module detects and errors on such conflicts
- HM module cannot detect (module system limitation)

### Testing Strategy

Uses [checkmate](https://github.com/vic/checkmate) with nix-unit for TDD:

1. **State tests**: Verify each state behaves correctly
2. **Precedence tests**: Ensure pathManager wins conflicts
3. **Persistence tests**: Check impermanence integration

Tests run in CI on each commit.

## Real-World Use Case

**Problem**: Chromium cookies wiped on reboot with impermanence

**Before**:
```nix
# Conflicting declarations!
home.file.".config/chromium/Default".source = ...;  # HM creates symlink
home.persistence."/persist/...".files = [ ".config/chromium/Default" ];  # Impermanence also manages it
# Result: Read-only symlink, cookies can't persist
```

**After**:
```nix
# Single source of truth
pathManager.users.alice = {
  ".config/chromium/Default" = mkMutablePath;  # Just persist, don't manage
};
# Result: Directory persisted, cookies work!
```

## Contributing

- Report issues on GitHub
- PRs welcome for additional tests, documentation
- Follow existing code style (enforced by `nix fmt`)

## License

MIT (or whatever you choose)
