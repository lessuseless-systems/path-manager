# TODO

## High Priority

### Migration Safety (Data Loss Prevention)

**Status:** Not started
**Priority:** High
**Complexity:** Medium

Safe-by-default approach to prevent data loss during pathManager adoption.

#### The Problem

Mutable/extensible paths can shadow existing data during activation:
- Data exists at `/home/user/.local/share/app/` (on root)
- Not yet in `/persist/home/user/.local/share/app/`
- Bind mount shadows it
- After reboot: root wiped, data lost

This is especially dangerous with erase-your-darlings / btrfs rollback setups where `/` is wiped on every boot.

#### Proposed Solution: 4-Layer Defense

**Layer 1: Dry-Run Mode (DEFAULT)**
- First activation shows what WOULD happen
- No bind mounts created
- No data modified
- User reviews warnings safely
- Explicit opt-in required (`dryRun = false`)

**Layer 2: Migration Modes**
- `"warn"`: Show warnings, require confirmation (default when `dryRun = false`)
- `"error"`: Abort if shadowing detected (conservative)
- `"auto"`: Automatically migrate data (convenient)
- `"disabled"`: No checks (not recommended)

**Layer 3: Auto-Migration with Backups**
- Automatically copy data to persist
- Create timestamped backups in `/persist/pathmanager-backups/`
- Preserve ownership/permissions

**Layer 4: Pre-Migration Helper Script**
- Interactive script to migrate data before activation
- `nix run .#path-manager-migrate`
- Review and confirm each path

#### User Workflow

**First Activation (Safe Default):**
```nix
home.pathManager.paths = {
  ".local/share/nvim/" = { state = "mutable"; };
};
# dryRun = true (implicit default - nothing actually happens)
```

**Output:**
```
🔍 pathManager dry-run mode (set dryRun = false to activate)

Scanning mutable/extensible paths:
  ✓ .config/nvim → immutable (symlink to nix store)

  ⚠️  .local/share/nvim/ → mutable
      Root: /home/user/.local/share/nvim (EXISTS - 245 MB)
      Persist: /persist/home/user/.local/share/nvim (MISSING)

      ⚠️  This data would be SHADOWED and LOST on reboot!

      Migration options:
      1. Run: nix run .#path-manager-migrate
      2. Or set: migrationMode = "auto"; dryRun = false;
      3. Or manually: sudo cp -a /home/user/.local/share/nvim /persist/home/user/

════════════════════════════════════════════════════════════
⚠️  Dry-run complete. NO bind mounts created.
   Review warnings above, then choose migration strategy.
════════════════════════════════════════════════════════════
```

**After Choosing Migration Strategy:**

**Option A - Interactive helper:**
```bash
nix run .#path-manager-migrate
# Interactive prompts to migrate each path
# Then set dryRun = false and activate
```

**Option B - Auto-migrate:**
```nix
home.pathManager = {
  dryRun = false;           # Activate bind mounts
  migrationMode = "auto";   # Auto-migrate on activation
  migrationBackup = true;   # Create backups (default)

  paths = {
    ".local/share/nvim/" = { state = "mutable"; };
  };
};
```

**Option C - Manual migration:**
```bash
# Migrate data manually first
sudo mkdir -p /persist/home/$USER/.local/share
sudo cp -a ~/.local/share/nvim /persist/home/$USER/.local/share/
sudo chown -R $USER:$USER /persist/home/$USER/.local/share/nvim
```
```nix
home.pathManager = {
  dryRun = false;  # I've migrated manually, safe to activate

  paths = {
    ".local/share/nvim/" = { state = "mutable"; };
  };
};
```

#### Implementation Details

**New Options:**
```nix
options.home.pathManager = {
  dryRun = mkOption {
    type = types.bool;
    default = true;  # SAFE DEFAULT - analyze but don't modify
    description = ''
      When true, pathManager analyzes your config and shows what it would do,
      but doesn't actually create bind mounts or modify anything.

      This is the safe default for first-time users. After reviewing warnings
      and migrating data, set to false to activate.
    '';
  };

  migrationMode = mkOption {
    type = types.enum [ "warn" "error" "auto" "disabled" ];
    default = "warn";
    description = ''
      How to handle data that would be shadowed (when dryRun = false):

      - "warn": Show warnings, require confirmation to continue
      - "error": Abort activation if shadowing detected
      - "auto": Automatically migrate data to persist
      - "disabled": No safety checks (not recommended)
    '';
  };

  migrationBackup = mkOption {
    type = types.bool;
    default = true;
    description = ''
      When auto-migrating, create timestamped backups in:
      /persist/pathmanager-backups/YYYY-MM-DD-HH-MM-SS/

      Highly recommended for safety. Backups can be cleaned up after
      verifying migration succeeded.
    '';
  };
};
```

**Files to Create/Modify:**

1. **modules/home-manager/path-manager/default.nix**
   - Add `dryRun`, `migrationMode`, `migrationBackup` options
   - Add `home.activation.pathManagerCheck` script
   - Dry-run: scan and report, no modifications
   - Migration modes: warn/error/auto/disabled logic
   - Auto-migration: copy with backups

2. **packages/path-manager-migrate.nix** (new)
   - Interactive helper script
   - Evaluate user's config to find pathManager declarations
   - For each mutable/extensible path:
     - Check if exists on root
     - Check if exists in persist
     - Prompt to migrate
     - Copy preserving attributes
     - Verify success

3. **tests/migration-safety.nix** (new)
   - Test dry-run detection (finds shadowed data)
   - Test migration mode "warn" (shows warnings)
   - Test migration mode "error" (aborts)
   - Test migration mode "auto" (copies data)
   - Test backup creation
   - Test permissions preservation

4. **MIGRATION.md**
   - Add "Migration Safety" section
   - Document the 4-layer approach
   - Add troubleshooting: "What if I already lost data?"
   - Add examples for common apps (nvim, doom, vscode)

**Benefits:**

✅ **Impossible to lose data accidentally** - dry-run is default
✅ **Clear warnings** with actionable instructions
✅ **Multiple migration strategies** for different user preferences
✅ **Explicit opt-in** - no surprises, user must acknowledge
✅ **Backup safety net** when auto-migrating
✅ **Works with both tmpfs and disk-based impermanence**

**Edge Cases to Handle:**

- Permissions (might need sudo for some paths)
- Large data (show progress during auto-migration)
- Symlinks (preserve or follow?)
- Hard links (preserve link structure)
- Read-only files (handle errors gracefully)
- Existing data in persist (merge or skip?)

---

### Multiple Persistence Roots Support

**Status:** Not started
**Priority:** Medium
**Complexity:** Medium

#### Problem

Currently, path-manager only supports a single persistence root. Users may want different paths persisted to different locations for various reasons:

- **Different storage devices**: SSD for cache, HDD for archival data
- **Different backup policies**: Don't backup `/cache`, do backup `/state`
- **Different encryption**: Secrets in encrypted partition, cache unencrypted
- **Different mount points**: System state vs user data vs temporary persistence

#### Current Limitation

```nix
home.pathManager = {
  persistenceRoot = "/persist/home/${config.home.username}";  # Single root only!

  paths = {
    ".config/nvim/" = { state = "mutable"; };  # Goes to /persist
    ".cache/" = { state = "mutable"; };        # Also goes to /persist
    # Can't send different paths to different persistence locations
  };
};
```

#### Proposed Solution: Option 1 Extended

Per-path overrides with optional named roots for convenience.

```nix
home.pathManager = {
  # Global default (covers 90% of use cases)
  persistenceRoot = "/persist/home/${config.home.username}";

  # Optional: named shortcuts for common overrides (syntactic sugar)
  persistenceRoots = {
    cache = "/persist/cache/${config.home.username}";
    state = "/persist/state/${config.home.username}";
    secrets = "/persist/encrypted/${config.home.username}";
  };

  paths = {
    # Uses default persistenceRoot
    ".config/nvim/" = {
      state = "mutable";
    };

    # Uses named root (references persistenceRoots.cache)
    ".cache/browser/" = {
      state = "mutable";
      root = "cache";
    };

    # Direct override (no named root needed)
    ".local/share/app/" = {
      state = "mutable";
      persistenceRoot = "/mnt/data/${config.home.username}";
    };

    # Uses named root for secrets
    ".ssh/" = {
      state = "mutable";
      root = "secrets";
    };
  };
};
```

#### Implementation Plan

1. **Update Path Declaration Submodule**
   - Add optional `root` field (string, references persistenceRoots key)
   - Add optional `persistenceRoot` field (string, direct path override)
   - Validation: error if both `root` and `persistenceRoot` are set

2. **Add `persistenceRoots` Option**
   - Type: `attrsOf str`
   - Default: `{}`
   - Description: Named persistence root shortcuts

3. **Update Config Logic**
   - Resolution order for each path:
     1. If `persistenceRoot` is set on path → use it
     2. Else if `root` is set on path → lookup in `persistenceRoots.${root}`
     3. Else → use global `persistenceRoot`
   - Group paths by resolved persistence root
   - Generate multiple `home.persistence.*` entries (one per unique root)
   - Same for `systemd.tmpfiles.rules` (use correct root path)

4. **Update Validation Library**
   - `detectExactConflicts`: Need to check each persistence root separately
   - `detectHierarchicalConflicts`: Group by persistence root before checking
   - Update NixOS module to handle multiple roots

5. **Update Tests**
   - Add tests/multiple-persistence-roots.nix (already exists, expand it)
   - Test named roots (`root = "cache"`)
   - Test direct overrides (`persistenceRoot = "/path"`)
   - Test mixed usage (some paths use default, some override)
   - Test validation across different roots
   - Test error cases (invalid root name, both root and persistenceRoot set)

6. **Documentation**
   - Update README.md with multiple roots examples
   - Update MIGRATION.md if API changes
   - Add use case examples (cache vs state vs secrets)

#### Files to Modify

- `modules/home-manager/path-manager/default.nix` - Add options and resolution logic
- `lib/validation.nix` - Group by persistence root before validation
- `modules/nixos/default.nix` - Handle multiple roots in NixOS module
- `tests/persistence-roots.nix` - Expand test coverage
- `README.md` - Document multiple roots feature
- `MIGRATION.md` - If breaking changes (unlikely)

#### Backward Compatibility

✅ **Fully backward compatible**
- Existing single-root configurations work unchanged
- `persistenceRoot` (singular) remains the simple case
- `persistenceRoots` (plural) and per-path overrides are opt-in

#### Example Use Cases

**Cache on fast storage, state on slow storage:**
```nix
home.pathManager = {
  persistenceRoot = "/persist/state/${config.home.username}";  # Default: persistent state
  persistenceRoots.cache = "/persist/cache/${config.home.username}";  # Fast SSD

  paths = {
    ".cache/" = { state = "mutable"; root = "cache"; };
    ".local/state/" = { state = "mutable"; };  # Uses default
  };
};
```

**Secrets in encrypted partition:**
```nix
home.pathManager = {
  persistenceRoot = "/persist/${config.home.username}";
  persistenceRoots.secrets = "/persist/encrypted/${config.home.username}";

  paths = {
    ".ssh/" = { state = "mutable"; root = "secrets"; };
    ".gnupg/" = { state = "mutable"; root = "secrets"; };
    ".config/" = { state = "mutable"; };  # Not secret, uses default
  };
};
```

---

## Medium Priority

### macOS/Darwin Support (launchd)

**Status:** Not started
**Priority:** Medium
**Complexity:** High

#### Problem

Currently, extensible paths (initial content) are not supported on macOS/Darwin.

```nix
# Linux: Works via systemd.tmpfiles.rules
systemd.tmpfiles.rules = [ "C /persist/home/user/.config/app ${content} -" ];

# macOS: TODO placeholder
launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
  # ... placeholder for launchd agent ...
};
```

#### What Works on macOS

✅ Immutable paths (`state = "immutable"`) - via home.file
✅ Mutable paths (`state = "mutable"`) - via home.persistence
✅ Ephemeral paths (`state = "ephemeral"`) - no action needed
❌ Extensible paths (`state = "extensible"`) - requires launchd implementation

#### Proposed Solution

Implement launchd agent that runs at login to initialize extensible paths.

```nix
launchd.agents.path-manager-init = lib.mkIf (pkgs.stdenv.isDarwin && hasExtensiblePaths) {
  enable = true;
  config = {
    ProgramArguments = [
      "${pkgs.writeScript "path-manager-init" ''
        #!/bin/sh
        # Initialize extensible paths if they don't exist
        ${initializationCommands}
      ''}"
    ];
    RunAtLoad = true;
    StandardOutPath = "/tmp/path-manager-init.log";
    StandardErrorPath = "/tmp/path-manager-init.err";
  };
};
```

#### Resources

- https://www.launchd.info/
- https://nix-community.github.io/home-manager/options.html#opt-launchd.agents
- https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html

#### Files to Modify

- `modules/home-manager/path-manager/default.nix` - Implement launchd.agents logic
- `tests/` - Add macOS-specific tests (may need Darwin test infrastructure)
- `README.md` - Update platform support documentation

---

## Low Priority

### Auto-Discovery of Persistence Root

**Status:** Not started
**Priority:** Low
**Complexity:** Low

#### Problem

Currently, if user doesn't set `persistenceRoot`, it defaults to `/persist/home/${config.home.username}`.

Could we auto-discover it from `home.persistence` config?

#### Proposed Solution

```nix
# Auto-discovery logic
persistenceRoot = mkOption {
  type = types.str;
  default =
    let
      persistenceRoots = attrNames (config.home.persistence or {});
      rootCount = length persistenceRoots;
    in
    if rootCount == 1 then
      head persistenceRoots  # Use the only persistence root
    else if rootCount > 1 then
      # Multiple roots exist, can't auto-detect
      # Fall back to convention
      "/persist/home/${config.home.username}"
    else
      # No persistence configured
      "/persist/home/${config.home.username}";
};
```

#### Considerations

- What if impermanence module is not loaded? (persistence config doesn't exist)
- What if user has multiple roots but wants path-manager to use a specific one?
- Explicit is better than implicit (current approach)

**Conclusion:** Nice-to-have but probably unnecessary. Explicit default is clearer.

---

## Completed

✅ **Test Suite Modularization** - Split 2196-line test file into 15 focused category files (v0.1.0)
✅ **Configurable Persistence Root** - Made persistence root configurable via `persistenceRoot` option (v0.2.0)
✅ **Comprehensive Conflict Detection** - Full recursive tree analysis for hierarchical conflicts (v0.1.0)
✅ **Type Detection System** - Automatic file vs directory inference with fallback heuristics (v0.1.0)
✅ **Dual-Module Architecture** - Separate HM and NixOS modules for appropriate validation levels (v0.1.0)

---

## Ideas / Future Exploration

### Path Groups

Allow defining groups of related paths:

```nix
home.pathManager = {
  groups.browser = {
    persistenceRoot = "/persist/browser/${config.home.username}";
    paths = {
      ".mozilla/" = { state = "mutable"; };
      ".cache/mozilla/" = { state = "mutable"; };
    };
  };

  groups.development = {
    persistenceRoot = "/persist/dev/${config.home.username}";
    paths = {
      ".config/nvim/" = { state = "mutable"; };
      ".local/share/nvim/" = { state = "mutable"; };
    };
  };
};
```

**Pros:** Logical organization, DRY for persistence roots
**Cons:** Adds complexity, may be overkill

### Hooks / Lifecycle Events

Allow running commands before/after path initialization:

```nix
".config/app/" = {
  state = "extensible";
  hooks = {
    afterInit = "chmod 700 ~/.config/app";
    beforePersist = "app --cleanup";
  };
};
```

**Use cases:** Permission management, cleanup, validation
**Complexity:** High, needs careful design

### Conditional Paths

Enable paths based on conditions:

```nix
".config/gaming/" = {
  state = "mutable";
  enable = config.programs.gaming.enable;
};
```

**Status:** Already possible via Nix conditionals, may not need special support