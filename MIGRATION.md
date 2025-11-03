# Migration Guide

## v0.2.0 - Configurable Persistence Root

### Breaking Changes

#### 1. API Structure Change

**Old API (v0.1.x):**
```nix
home.pathManager.".bashrc" = {
  state = "immutable";
  text = "...";
};
```

**New API (v0.2.x):**
```nix
home.pathManager.paths.".bashrc" = {
  state = "immutable";
  text = "...";
};
```

**Migration Steps:**

1. Add `.paths` after `home.pathManager` in all your declarations
2. Optionally configure persistence root if not using the default

**Automated Migration:**
```bash
# In your NixOS configuration directory
find . -name "*.nix" -type f -exec sed -i 's/home\.pathManager = {/home.pathManager.paths = {/g' {} \;
```

#### 2. Configurable Persistence Root

The persistence root is now configurable, allowing integration with non-standard impermanence setups.

**Default Behavior (no changes needed for `/persist` setups):**
```nix
# This is the default - works with impermanence setups using /persist
home.pathManager.persistenceRoot = "/persist/home/${config.home.username}";

# If you use /persistent or another path, you'll need to configure it (see below)
```

**Custom Persistence Root Examples:**

```nix
# Using /persistent (common alternative)
home.pathManager = {
  persistenceRoot = "/persistent/home/${config.home.username}";

  paths = {
    ".bashrc" = { state = "immutable"; text = "..."; };
  };
};

# Using /nix/persist (explicit nix-specific)
home.pathManager = {
  persistenceRoot = "/nix/persist/home/${config.home.username}";

  paths = {
    ".bashrc" = { state = "immutable"; text = "..."; };
  };
};

# Using a completely custom path
home.pathManager = {
  persistenceRoot = "/mnt/persistence/${config.home.username}";

  paths = {
    ".bashrc" = { state = "immutable"; text = "..."; };
  };
};
```

### New Features

✅ **Configurable Persistence Root** - Set `home.pathManager.persistenceRoot` to match your impermanence setup
✅ **Better Integration** - Works with dendritic flake-parts-based configurations
✅ **No Hardcoded Paths** - Fully parameterized for flexibility

### Compatibility

- **Home Manager**: Compatible with all versions that support impermanence
- **Impermanence Module**: Works with standard `home.persistence.*` structure
- **Platform**: Linux (systemd.tmpfiles) fully supported, macOS (launchd) TODO

### Platform Notes

#### Linux (Supported ✓)
Uses `systemd.tmpfiles.rules` for extensible path initialization. Fully functional.

#### macOS/Darwin (Limited Support ⚠️)
The `launchd.agents` implementation is a TODO placeholder. If you're on macOS:
- Immutable, mutable, and ephemeral paths work
- Extensible paths (initial content) are not yet supported
- PRs welcome for Darwin support!

### Type Detection Limitations

The module uses `builtins.pathExists` to detect if a source is a directory:

```nix
# This works if ./my-dir exists at eval time
".config/app" = { state = "immutable"; source = ./my-dir; };

# This also works (heuristic detection)
".config/app/" = { state = "mutable"; };  # trailing slash → directory
```

**Fallback Heuristics:**
1. Trailing slash (`/`) → directory
2. Explicit `type = "directory"` override
3. No source/text + mutable/ephemeral → directory (default)

### Examples

#### Before (v0.1.x)
```nix
{
  home.pathManager = {
    ".bashrc" = { state = "immutable"; text = "export PATH=..."; };
    ".config/nvim/" = { state = "mutable"; };
    ".cache/" = { state = "ephemeral"; };
  };
}
```

#### After (v0.2.x - standard setup)
```nix
{
  home.pathManager.paths = {
    ".bashrc" = { state = "immutable"; text = "export PATH=..."; };
    ".config/nvim/" = { state = "mutable"; };
    ".cache/" = { state = "ephemeral"; };
  };
}
```

#### After (v0.2.x - custom persistence root)
```nix
{
  home.pathManager = {
    persistenceRoot = "/nix/persist/home/${config.home.username}";

    paths = {
      ".bashrc" = { state = "immutable"; text = "export PATH=..."; };
      ".config/nvim/" = { state = "mutable"; };
      ".cache/" = { state = "ephemeral"; };
    };
  };
}
```

### Helper Functions (Unchanged)

The library helper functions are unchanged:

```nix
let
  pathManagerLib = inputs.path-manager.lib;
in
{
  home.pathManager.paths = {
    ".bashrc" = pathManagerLib.mkImmutablePath { text = "..."; };
    ".config/nvim/" = pathManagerLib.mkMutablePath;
    ".cache/" = pathManagerLib.mkEphemeralPath;
  };
}
```

### Need Help?

- Check the README.md for updated examples
- See tests/ directory for comprehensive usage examples
- Open an issue on GitHub if you encounter problems

### Rollback

If you need to rollback to v0.1.x:

```nix
inputs.path-manager.url = "github:yourorg/path-manager?ref=v0.1.0";
```

Then revert the `.paths` changes in your configuration.