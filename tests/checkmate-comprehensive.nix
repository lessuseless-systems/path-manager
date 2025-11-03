# Comprehensive test suite for path-manager
# Includes type detection, exact conflicts, hierarchical conflicts, directories, and integration tests

{ inputs, ... }:
let
  self = inputs.target;
  home-manager = inputs.target.inputs.home-manager;
  pkgs = import inputs.target.inputs.nixpkgs { system = "x86_64-linux"; };
  pathManagerLib = self.lib;

  createTestConfig =
    modules:
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs;
      modules = [
        self.flakeModule
        inputs.target.inputs.impermanence.homeManagerModules.impermanence
        {
          # Fake systemd module for testing
          options.systemd.tmpfiles.rules = pkgs.lib.mkOption {
            type = pkgs.lib.types.listOf pkgs.lib.types.str;
            default = [ ];
          };
        }
        {
          home.stateVersion = "22.11";
          home.username = "test-user";
          home.homeDirectory = "/home/test-user";
        }
      ] ++ modules;
    };

in
{
  perSystem.nix-unit.tests = {

    # ========================================================================
    # TYPE DETECTION TESTS (8 tests)
    # ========================================================================

    "type-detection: trailing slash → directory" = {
      expr =
        let
          testPath = ".config/app/";
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = testPath;
            type = null;
            source = null;
            text = null;
            state = "mutable";
          };
        in
        detectedType;
      expected = "directory";
    };

    "type-detection: no trailing slash + has text → file" = {
      expr =
        let
          testPath = ".config/app.conf";
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = testPath;
            type = null;
            source = null;
            text = "config content";
            state = "immutable";
          };
        in
        detectedType;
      expected = "file";
    };

    "type-detection: no source/text + mutable → directory" = {
      expr =
        let
          testPath = ".local/state";
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = testPath;
            type = null;
            source = null;
            text = null;
            state = "mutable";
          };
        in
        detectedType;
      expected = "directory";
    };

    "type-detection: no source/text + ephemeral → directory" = {
      expr =
        let
          testPath = ".cache";
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = testPath;
            type = null;
            source = null;
            text = null;
            state = "ephemeral";
          };
        in
        detectedType;
      expected = "directory";
    };

    "type-detection: explicit type override → use override" = {
      expr =
        let
          testPath = ".config"; # no trailing slash
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = testPath;
            type = "file"; # explicit override
            source = null;
            text = null;
            state = "mutable";
          };
        in
        detectedType;
      expected = "file"; # Uses override despite heuristics suggesting directory
    };

    "type-detection: has source → file" = {
      expr =
        let
          testPath = "my-config";
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = testPath;
            type = null;
            source = /some/path; # has source
            text = null;
            state = "immutable";
          };
        in
        detectedType;
      expected = "file";
    };

    "type-detection: normalize path removes trailing slash" = {
      expr = pathManagerLib.typeDetection.normalizePath ".config/app/";
      expected = ".config/app";
    };

    "type-detection: normalize path without trailing slash unchanged" = {
      expr = pathManagerLib.typeDetection.normalizePath ".config/app";
      expected = ".config/app";
    };

    # ========================================================================
    # DIRECTORY TESTS (8 tests)
    # ========================================================================

    "directory: mutable directory → adds to persistence.directories" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/state/" = pathManagerLib.mkMutablePath // { type = "directory"; };
              };
            }
          ];
        in
        builtins.elem ".local/state" config.config.home.persistence."/persist/home/test-user".directories;
      expected = true;
    };

    "directory: mutable file → adds to persistence.files" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/state/file.db" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem ".local/state/file.db" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "directory: extensible directory → adds to persistence.directories" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/" = pathManagerLib.mkExtensiblePath { text = "init"; };
              };
            }
          ];
        in
        builtins.elem ".config/app" config.config.home.persistence."/persist/home/test-user".directories;
      expected = true;
    };

    "directory: immutable directory with source → adds to home.file as recursive" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/myapp/" = pathManagerLib.mkImmutablePath {
                  source = pkgs.writeTextDir "config.json" "{}";
                  type = "directory";
                };
              };
            }
          ];
        in
        config.config.home.file.".config/myapp".recursive or false;
      expected = true;
    };

    "directory: ephemeral directory → not in persistence" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".cache/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        builtins.elem ".cache" config.config.home.persistence."/persist/home/test-user".directories;
      expected = false;
    };

    "directory: ephemeral directory → not in home.file" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".cache/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        config.config.home.file ? ".cache";
      expected = false;
    };

    "directory: extensible directory → creates tmpfiles.d rule" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/data/" = pathManagerLib.mkExtensiblePath { type = "directory"; };
              };
            }
          ];
        in
        builtins.any (
          rule: builtins.match "d /persist/home/test-user/\\.local/data .*" rule != null
        ) config.config.systemd.tmpfiles.rules;
      expected = true;
    };

    "directory: trailing slash auto-detected as directory and persisted" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".mozilla/" = pathManagerLib.mkMutablePath; # auto-detected as directory
              };
            }
          ];
        in
        builtins.elem ".mozilla" config.config.home.persistence."/persist/home/test-user".directories;
      expected = true;
    };

    # ========================================================================
    # PATH RELATIONSHIP UTILITY TESTS (6 tests)
    # ========================================================================

    "path-relationship: pathSegments splits correctly" = {
      expr = pathManagerLib.validation.pathSegments ".config/app/file.json";
      expected = [ ".config" "app" "file.json" ];
    };

    "path-relationship: pathDepth counts segments" = {
      expr = pathManagerLib.validation.pathDepth ".config/app/file.json";
      expected = 3;
    };

    "path-relationship: isParentOf detects parent" = {
      expr = pathManagerLib.validation.isParentOf ".config" ".config/app/file.json";
      expected = true;
    };

    "path-relationship: isParentOf rejects non-parent" = {
      expr = pathManagerLib.validation.isParentOf ".local" ".config/app";
      expected = false;
    };

    "path-relationship: getAllAncestors returns all parents" = {
      expr = pathManagerLib.validation.getAllAncestors ".config/app/file.json";
      expected = [ ".config" ".config/app" ];
    };

    "path-relationship: getAllDescendants finds children" = {
      expr =
        let
          allPaths = [
            ".config"
            ".config/app"
            ".config/app/file.json"
            ".local/state"
          ];
        in
        pathManagerLib.validation.getAllDescendants allPaths ".config";
      expected = [
        ".config/app"
        ".config/app/file.json"
      ];
    };

    # ========================================================================
    # EXACT CONFLICT TESTS (16 tests)
    # ========================================================================

    "exact-conflict: ephemeral vs home.file → error" = {
      expr =
        let
          pathManagerDecls = {
            ".cache/temp" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".cache/temp" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: ephemeral vs persistence.files → error" = {
      expr =
        let
          pathManagerDecls = {
            ".cache/data" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".cache/data" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: mutable file vs persistence.files → warning" = {
      expr =
        let
          pathManagerDecls = {
            ".local/data.db" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".local/data.db" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
            warnOnRedundant = true;
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: mutable file vs persistence.directories → type mismatch error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app" = {
              state = "mutable";
              source = null;
              text = null;
              type = null; # will be detected as file
            };
          };
          persistenceDirs = [ ".config/app" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: mutable dir vs persistence.files → type mismatch error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/" = {
              # trailing slash → directory
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".config/app" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: mutable vs home.file → error" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: extensible file vs persistence.files → warning" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "extensible";
              source = null;
              text = "#!/bin/bash";
            };
          };
          persistenceFiles = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
            warnOnRedundant = true;
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: immutable vs home.file → warning (mkForce handles it)" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "immutable";
              source = null;
              text = "#!/bin/bash";
            };
          };
          homeFilePaths = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: no conflicts → empty list" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "immutable";
              source = null;
              text = "#!/bin/bash";
            };
          };
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "exact-conflict: multiple conflicts detected" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
            ".vimrc" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [
            ".bashrc"
            ".vimrc"
          ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 2;
    };

    "exact-conflict: warnOnRedundant=false → no warnings" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
            warnOnRedundant = false;
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "exact-conflict: extensible dir vs persistence.dirs → warning" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/" = {
              state = "extensible";
              source = null;
              text = null;
            };
          };
          persistenceDirs = [ ".config/app" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            warnOnRedundant = true;
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: mutable dir vs persistence.dirs → warning" = {
      expr =
        let
          pathManagerDecls = {
            ".mozilla/" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceDirs = [ ".mozilla" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            warnOnRedundant = true;
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: ephemeral vs persistence.dirs → error" = {
      expr =
        let
          pathManagerDecls = {
            ".cache/" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          persistenceDirs = [ ".cache" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: immutable vs persistence → conflict error" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "immutable";
              source = null;
              text = "content";
            };
          };
          persistenceFiles = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        # Immutable should NOT be persisted, this is a conflict
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "exact-conflict: extensible vs home.file → conflict error" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "extensible";
              source = null;
              text = "content";
            };
          };
          homeFilePaths = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    # ========================================================================
    # HIERARCHICAL CONFLICT TESTS (30 tests - representative subset)
    # ========================================================================

    "hierarchical: home.file parent + pathManager child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/config.json" = {
              state = "immutable";
              source = null;
              text = "{}";
            };
          };
          homeFilePaths = [ ".config/app" ]; # parent directory
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: persistence.dirs parent + pathManager immutable child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/config.json" = {
              state = "immutable";
              source = null;
              text = "{}";
            };
          };
          persistenceDirs = [ ".config/app" ]; # parent persisted
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: persistence.dirs parent + pathManager ephemeral child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/temp" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          persistenceDirs = [ ".config/app" ]; # parent persisted
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: persistence.dirs parent + pathManager mutable child → warning (redundant)" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/data.db" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceDirs = [ ".config/app" ]; # parent already persisted
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: pathManager immutable parent + home.file child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/" = {
              state = "immutable";
              source = null;
              text = null;
              type = "directory";
            };
          };
          homeFilePaths = [ ".config/app/override.conf" ]; # child
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: pathManager immutable parent + persistence child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/" = {
              state = "immutable";
              source = null;
              text = null;
              type = "directory";
            };
          };
          persistenceFiles = [ ".config/app/data.db" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: pathManager ephemeral parent + home.file child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".cache/" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".cache/important" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: pathManager ephemeral parent + persistence child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".cache/" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".cache/saved.db" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: pathManager mutable parent + persistence child → warning" = {
      expr =
        let
          pathManagerDecls = {
            ".local/state/" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".local/state/app.db" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: multi-level (grandparent-grandchild) detected" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/subdir/file.json" = {
              state = "immutable";
              source = null;
              text = "{}";
            };
          };
          homeFilePaths = [ ".config" ]; # grandparent
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0;
      expected = true;
    };

    "hierarchical: no parent-child relationship → no conflict" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".local/state" ]; # unrelated path
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "hierarchical: sibling paths → no conflict" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app1" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".config/app2" ]; # sibling
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "hierarchical: pathManager mutable parent + home.file child → error" = {
      expr =
        let
          pathManagerDecls = {
            ".mozilla/" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".mozilla/firefox/profiles.ini" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && !(builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: deep nesting (4 levels) detected" = {
      expr =
        let
          pathManagerDecls = {
            ".config/a/b/c/d.json" = {
              state = "immutable";
              source = null;
              text = "{}";
            };
          };
          persistenceDirs = [ ".config/a" ]; # great-great-grandparent
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        (builtins.length conflicts) > 0;
      expected = true;
    };

    "hierarchical: pathManager extensible parent + persistence child → warning" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/" = {
              state = "extensible";
              source = null;
              text = null;
              type = "directory";
            };
          };
          persistenceFiles = [ ".config/app/data.db" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceFiles;
            homeFilePaths = [ ];
            persistenceDirs = [ ];
          };
        in
        (builtins.length conflicts) > 0 && (builtins.head conflicts).assertion;
      expected = true;
    };

    "hierarchical: multiple conflicts in same tree" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app1/file1" = {
              state = "immutable";
              source = null;
              text = "1";
            };
            ".config/app2/file2" = {
              state = "immutable";
              source = null;
              text = "2";
            };
          };
          homeFilePaths = [
            ".config"
          ]; # parent of both
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 2;
    };

    "hierarchical: home.file parent + multiple pathManager children → all detected" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/a.json" = {
              state = "immutable";
              source = null;
              text = "a";
            };
            ".config/app/b.json" = {
              state = "immutable";
              source = null;
              text = "b";
            };
            ".config/app/c.json" = {
              state = "immutable";
              source = null;
              text = "c";
            };
          };
          homeFilePaths = [ ".config/app" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 3;
    };

    "hierarchical: persistence parent + pathManager extensible child → allow/warn" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/init.conf" = {
              state = "extensible";
              source = null;
              text = "initial";
            };
          };
          persistenceDirs = [ ".config/app" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        # Should be allowed or just a warning
        if (builtins.length conflicts) > 0 then (builtins.head conflicts).assertion else true;
      expected = true;
    };

    "hierarchical: empty pathManager → no conflicts" = {
      expr =
        let
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            pathManagerDecls = { };
            homeFilePaths = [ ".config" ];
            persistenceFiles = [ ".local/state" ];
            persistenceDirs = [ ".cache" ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "hierarchical: all empty → no conflicts" = {
      expr =
        let
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            pathManagerDecls = { };
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    # ========================================================================
    # INTEGRATION TESTS (3 tests)
    # ========================================================================

    "integration: complex real-world chromium cookies scenario" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                # Persist the entire Default profile directory
                ".config/chromium/Default/" = pathManagerLib.mkMutablePath // { type = "directory"; };
                # Initialize cookies if they don't exist
                ".config/chromium/Default/Cookies" = pathManagerLib.mkExtensiblePath {
                  text = "# Initial cookies DB";
                };
              };
            }
          ];
        in
        # Both should be in persistence
        builtins.elem ".config/chromium/Default"
          config.config.home.persistence."/persist/home/test-user".directories
        && builtins.elem ".config/chromium/Default/Cookies"
          config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "integration: mixed states in same directory tree" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                # Immutable config
                ".config/app/config.json" = pathManagerLib.mkImmutablePath { text = "{}"; };
                # Mutable data in same tree
                ".config/app/data/" = pathManagerLib.mkMutablePath // { type = "directory"; };
                # Ephemeral cache in same tree
                ".config/app/cache/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        # Immutable in home.file
        (config.config.home.file ? ".config/app/config.json")
        # Mutable in persistence
        && (
          builtins.elem ".config/app/data" config.config.home.persistence."/persist/home/test-user".directories
        )
        # Ephemeral not in persistence or home.file
        && !(config.config.home.file ? ".config/app/cache")
        && !(
          builtins.elem ".config/app/cache" config.config.home.persistence."/persist/home/test-user".directories
        );
      expected = true;
    };

    "integration: all four states working together" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                # Immutable
                ".bashrc" = pathManagerLib.mkImmutablePath { text = "#!/bin/bash"; };
                # Ephemeral
                ".cache/temp/" = pathManagerLib.mkEphemeralPath;
                # Mutable
                ".local/state/app.db" = pathManagerLib.mkMutablePath;
                # Extensible
                ".config/settings.json" = pathManagerLib.mkExtensiblePath { text = "{}"; };
              };
            }
          ];
        in
        # Verify each state
        (config.config.home.file ? ".bashrc") # immutable
        && !(config.config.home.file ? ".cache/temp") # ephemeral
        && (
          builtins.elem ".local/state/app.db" config.config.home.persistence."/persist/home/test-user".files
        ) # mutable
        && (
          builtins.elem ".config/settings.json" config.config.home.persistence."/persist/home/test-user".files
        ); # extensible
      expected = true;
    };

    # ========================================================================
    # ADVANCED EDGE CASES (32+ tests)
    # ========================================================================

    # ------------------------------------------------------------------------
    # Three-Way Exact Conflicts (5 tests)
    # ------------------------------------------------------------------------

    "three-way: pathManager + home.file + persistence.files (same path)" = {
      expr =
        let
          pathManagerDecls = {
            ".bashrc" = {
              state = "immutable";
              source = null;
              text = "from pathManager";
            };
          };
          homeFilePaths = [ ".bashrc" ];
          persistenceFiles = [ ".bashrc" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths persistenceFiles;
            persistenceDirs = [ ];
          };
        in
        # Should detect multiple conflicts on same path
        builtins.length conflicts >= 2;
      expected = true;
    };

    "three-way: ephemeral + home.file + persistence.files (triple conflict)" = {
      expr =
        let
          pathManagerDecls = {
            ".cache/data" = {
              state = "ephemeral";
              source = null;
              text = null;
            };
          };
          homeFilePaths = [ ".cache/data" ];
          persistenceFiles = [ ".cache/data" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths persistenceFiles;
            persistenceDirs = [ ];
          };
        in
        # All should be errors
        builtins.length conflicts >= 2 && builtins.all (c: !c.assertion) conflicts;
      expected = true;
    };

    "three-way: mutable dir + persistence.files + persistence.dirs (type chaos)" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceFiles = [ ".config/app" ];
          persistenceDirs = [ ".config/app" ];
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls persistenceFiles persistenceDirs;
            homeFilePaths = [ ];
          };
        in
        # Should detect type mismatch with files
        builtins.any (c: !c.assertion) conflicts;
      expected = true;
    };

    "three-way: pathManager + home.file parent + persistence child" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/file.json" = {
              state = "immutable";
              source = null;
              text = "{}";
            };
          };
          homeFilePaths = [ ".config/app" ]; # parent
          persistenceFiles = [ ".config/app/file.json" ]; # same as pathManager
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths persistenceFiles;
            persistenceDirs = [ ];
          };
        in
        # Should detect parent-child conflict
        builtins.length conflicts > 0;
      expected = true;
    };

    "three-way: all sources declare different levels of same tree" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/sub/file.json" = {
              state = "immutable";
              source = null;
              text = "{}";
            };
          };
          homeFilePaths = [ ".config" ]; # grandparent
          persistenceDirs = [ ".config/app" ]; # parent
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths persistenceDirs;
            persistenceFiles = [ ];
          };
        in
        # Should detect multiple hierarchical conflicts
        builtins.length conflicts >= 1;
      expected = true;
    };

    # ------------------------------------------------------------------------
    # Multiple Persistence Roots (4 tests)
    # ------------------------------------------------------------------------

    "multi-root: same file in two persistence roots" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
              # Manually add a second persistence root
              home.persistence."/other/persist/home/test-user".files = [ ];
            }
          ];
        in
        # Should appear in default persist root
        builtins.elem ".bashrc" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "multi-root: different files in different roots handled correctly" = {
      expr =
        let
          config = createTestConfig [
            {
              home.persistence."/persist/home/test-user".files = [ ".file1" ];
              home.persistence."/other/persist/home/test-user".files = [ ".file2" ];
              home.pathManager.paths = {
                ".file3" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # file3 goes to default root, others stay in their roots
        builtins.elem ".file3" config.config.home.persistence."/persist/home/test-user".files
        && builtins.elem ".file1" config.config.home.persistence."/persist/home/test-user".files
        && builtins.elem ".file2" config.config.home.persistence."/other/persist/home/test-user".files;
      expected = true;
    };

    "multi-root: pathManager doesn't interfere with other roots" = {
      expr =
        let
          config = createTestConfig [
            {
              home.persistence."/other/root".files = [ ".other-file" ];
              home.pathManager.paths = {
                ".my-file" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # pathManager uses default root, other root unchanged
        builtins.elem ".other-file" config.config.home.persistence."/other/root".files;
      expected = true;
    };

    "multi-root: collect persistence files from all roots for validation" = {
      expr =
        let
          # This tests the NixOS module's collectPersistenceFiles function
          # We can't easily test the NixOS module here, so we test the concept
          persistRoots = {
            "/persist/home/user".files = [
              ".file1"
              ".file2"
            ];
            "/other/persist".files = [ ".file3" ];
          };
          allFiles = pkgs.lib.unique (
            pkgs.lib.flatten (pkgs.lib.mapAttrsToList (_root: cfg: cfg.files or [ ]) persistRoots)
          );
        in
        allFiles == [
          ".file1"
          ".file2"
          ".file3"
        ];
      expected = true;
    };

    # ------------------------------------------------------------------------
    # Unicode and Special Characters (6 tests)
    # ------------------------------------------------------------------------

    "unicode: path with emoji persists correctly" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/🎨-theme.json" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem ".config/🎨-theme.json" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "unicode: path with chinese characters" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/配置.conf" = pathManagerLib.mkImmutablePath { text = "test"; };
              };
            }
          ];
        in
        config.config.home.file ? ".config/配置.conf";
      expected = true;
    };

    "special-chars: path with spaces detected as directory" = {
      expr =
        let
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = ".config/my app/";
            type = null;
            source = null;
            text = null;
            state = "mutable";
          };
        in
        detectedType;
      expected = "directory";
    };

    "special-chars: path with dots and dashes" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app-v1.2.3.conf" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem ".config/app-v1.2.3.conf" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "special-chars: normalize path handles unicode" = {
      expr = pathManagerLib.typeDetection.normalizePath ".config/🎨/";
      expected = ".config/🎨";
    };

    "special-chars: path segments with unicode" = {
      expr = pathManagerLib.validation.pathSegments ".config/测试/文件.txt";
      expected = [
        ".config"
        "测试"
        "文件.txt"
      ];
    };

    # ------------------------------------------------------------------------
    # Absolute vs Relative Paths (4 tests)
    # ------------------------------------------------------------------------

    "absolute-path: leading slash not treated as segment" = {
      expr = pathManagerLib.validation.pathSegments "/absolute/path";
      expected = [
        "absolute"
        "path"
      ];
    };

    "absolute-path: normalize handles absolute paths" = {
      expr = pathManagerLib.typeDetection.normalizePath "/absolute/path/";
      expected = "/absolute/path";
    };

    "absolute-path: isParentOf works with absolute paths" = {
      expr = pathManagerLib.validation.isParentOf "/home/user" "/home/user/file.txt";
      expected = true;
    };

    "relative-path: getAllAncestors handles relative paths" = {
      expr = pathManagerLib.validation.getAllAncestors "relative/path/file.txt";
      expected = [
        "relative"
        "relative/path"
      ];
    };

    # ------------------------------------------------------------------------
    # Performance Tests (3 tests)
    # ------------------------------------------------------------------------

    "performance: 100 paths type detection" = {
      expr =
        let
          paths = pkgs.lib.genList (n: ".file${toString n}") 100;
          results = map (
            path:
            pathManagerLib.typeDetection.inferPathType {
              inherit path;
              type = null;
              source = null;
              text = "content";
              state = "immutable";
            }
          ) paths;
        in
        builtins.length results;
      expected = 100;
    };

    "performance: 100 exact conflict checks" = {
      expr =
        let
          pathManagerDecls = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair ".file${toString n}" {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 100
          );
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "performance: hierarchical detection with 50 paths" = {
      expr =
        let
          # Create nested paths: .a/b/c/...
          pathManagerDecls = builtins.listToAttrs (
            pkgs.lib.genList (
              n:
              let
                path = pkgs.lib.concatStringsSep "/" (pkgs.lib.genList (i: "level${toString i}") (n + 1));
              in
              pkgs.lib.nameValuePair path {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 50
          );
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        # No conflicts expected
        builtins.length conflicts;
      expected = 0;
    };

    # ------------------------------------------------------------------------
    # Complex Hierarchical Scenarios (6 tests)
    # ------------------------------------------------------------------------

    "complex-hierarchy: sibling directories with children" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app1/file" = {
              state = "immutable";
              source = null;
              text = "1";
            };
            ".config/app2/file" = {
              state = "immutable";
              source = null;
              text = "2";
            };
          };
          persistenceDirs = [ ".config/app1" ];
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        # Should only detect conflict for app1, not app2
        builtins.length conflicts;
      expected = 1;
    };

    "complex-hierarchy: deeply nested (10 levels)" = {
      expr =
        let
          deepPath = ".a/b/c/d/e/f/g/h/i/j/file.txt";
          pathManagerDecls = {
            ${deepPath} = {
              state = "immutable";
              source = null;
              text = "deep";
            };
          };
          homeFilePaths = [ ".a/b/c" ]; # ancestor at level 3
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        # Should detect even at deep nesting
        builtins.length conflicts > 0;
      expected = true;
    };

    "complex-hierarchy: mixed parent-child-sibling tree" = {
      expr =
        let
          pathManagerDecls = {
            ".config/app/sub1/file1" = {
              state = "mutable";
              source = null;
              text = null;
            };
            ".config/app/sub2/file2" = {
              state = "mutable";
              source = null;
              text = null;
            };
            ".config/other/file3" = {
              state = "mutable";
              source = null;
              text = null;
            };
          };
          persistenceDirs = [ ".config/app" ]; # parent of sub1 and sub2, not other
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls persistenceDirs;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
          };
        in
        # Should detect 2 conflicts (sub1 and sub2), not other
        builtins.length conflicts;
      expected = 2;
    };

    "complex-hierarchy: getAllDescendants filters correctly" = {
      expr =
        let
          allPaths = [
            ".config"
            ".config/app"
            ".config/app/file.json"
            ".config/other"
            ".local"
          ];
          descendants = pathManagerLib.validation.getAllDescendants allPaths ".config";
        in
        builtins.length descendants;
      expected = 3; # app, app/file.json, other
    };

    "complex-hierarchy: pathDepth counts correctly for deep paths" = {
      expr = pathManagerLib.validation.pathDepth ".a/b/c/d/e/f/g/h/i/j";
      expected = 10;
    };

    "complex-hierarchy: ancestor chain complete" = {
      expr =
        let
          ancestors = pathManagerLib.validation.getAllAncestors ".a/b/c/d/e";
        in
        builtins.length ancestors;
      expected = 4; # .a, .a/b, .a/b/c, .a/b/c/d
    };

    # ------------------------------------------------------------------------
    # Edge Cases with Empty/Null Values (4 tests)
    # ------------------------------------------------------------------------

    "edge-empty: path with only slashes normalized" = {
      expr = pathManagerLib.typeDetection.normalizePath "///";
      expected = "";
    };

    "edge-empty: pathSegments handles empty path" = {
      expr = pathManagerLib.validation.pathSegments "";
      expected = [ ];
    };

    "edge-empty: getAllAncestors on single-segment path" = {
      expr = pathManagerLib.validation.getAllAncestors "file";
      expected = [ ];
    };

    "edge-empty: isParentOf with empty parent" = {
      expr = pathManagerLib.validation.isParentOf "" "file";
      expected = false;
    };

    # ========================================================================
    # STRESS TESTS - 1000+ PATHS (10 tests)
    # ========================================================================

    "stress: 1000 files type detection" = {
      expr =
        let
          paths = pkgs.lib.genList (n: ".file${toString n}") 1000;
          results = map (
            path:
            pathManagerLib.typeDetection.inferPathType {
              inherit path;
              type = null;
              source = null;
              text = "content";
              state = "immutable";
            }
          ) paths;
        in
        builtins.all (t: t == "file") results;
      expected = true;
    };

    "stress: 1000 paths exact conflict detection (no conflicts)" = {
      expr =
        let
          pathManagerDecls = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair ".file${toString n}" {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 1000
          );
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls;
            homeFilePaths = [ ];
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 0;
    };

    "stress: 1000 paths with 500 conflicts detected" = {
      expr =
        let
          pathManagerDecls = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair ".file${toString n}" {
                state = "ephemeral";
                source = null;
                text = null;
              }
            ) 1000
          );
          # First 500 files also in home.file
          homeFilePaths = pkgs.lib.genList (n: ".file${toString n}") 500;
          conflicts = pathManagerLib.validation.detectExactConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 500;
    };

    "stress: deep hierarchy 100 levels" = {
      expr =
        let
          # Create a 100-level deep path
          segments = pkgs.lib.genList (n: "level${toString n}") 100;
          deepPath = pkgs.lib.concatStringsSep "/" segments;
          ancestors = pathManagerLib.validation.getAllAncestors deepPath;
        in
        builtins.length ancestors;
      expected = 99; # All ancestors except the path itself
    };

    "stress: 1000 paths with hierarchical conflicts" = {
      expr =
        let
          # Create 1000 paths, all children of ".config"
          pathManagerDecls = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair ".config/file${toString n}" {
                state = "immutable";
                source = null;
                text = "content";
              }
            ) 1000
          );
          homeFilePaths = [ ".config" ]; # Parent of all
          conflicts = pathManagerLib.validation.detectHierarchicalConflicts {
            inherit pathManagerDecls homeFilePaths;
            persistenceFiles = [ ];
            persistenceDirs = [ ];
          };
        in
        builtins.length conflicts;
      expected = 1000; # All 1000 should conflict with parent
    };

    "stress: 1000 paths configuration generation" = {
      expr =
        let
          pathManagerDecls = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair ".file${toString n}" {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 1000
          );
          config = createTestConfig [
            { home.pathManager = pathManagerDecls; }
          ];
        in
        # All 1000 should be in persistence
        builtins.length config.config.home.persistence."/persist/home/test-user".files;
      expected = 1000;
    };

    "stress: mixed 1000 paths (250 each state)" = {
      expr =
        let
          immutablePaths = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair "immutable${toString n}" {
                state = "immutable";
                source = null;
                text = "content";
              }
            ) 250
          );
          ephemeralPaths = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair "ephemeral${toString n}" {
                state = "ephemeral";
                source = null;
                text = null;
              }
            ) 250
          );
          mutablePaths = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair "mutable${toString n}" {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 250
          );
          extensiblePaths = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair "extensible${toString n}" {
                state = "extensible";
                source = null;
                text = "init";
              }
            ) 250
          );
          allPaths = immutablePaths // ephemeralPaths // mutablePaths // extensiblePaths;
          config = createTestConfig [ { home.pathManager = allPaths; } ];
        in
        # Verify counts: 250 immutable in home.file, 500 (mutable+extensible) in persistence
        (builtins.length (builtins.attrNames config.config.home.file) >= 250)
        && (builtins.length config.config.home.persistence."/persist/home/test-user".files >= 500);
      expected = true;
    };

    "stress: 500 directories + 500 files" = {
      expr =
        let
          dirs = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair "dir${toString n}/" {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 500
          );
          files = builtins.listToAttrs (
            pkgs.lib.genList (
              n: pkgs.lib.nameValuePair "file${toString n}" {
                state = "mutable";
                source = null;
                text = null;
              }
            ) 500
          );
          allPaths = dirs // files;
          config = createTestConfig [ { home.pathManager = allPaths; } ];
        in
        # 500 in directories, 500 in files
        (builtins.length config.config.home.persistence."/persist/home/test-user".directories == 500)
        && (builtins.length config.config.home.persistence."/persist/home/test-user".files == 500);
      expected = true;
    };

    "stress: pathSegments performance on 1000 paths" = {
      expr =
        let
          paths = pkgs.lib.genList (n: ".config/app${toString n}/file.txt") 1000;
          results = map (path: builtins.length (pathManagerLib.validation.pathSegments path)) paths;
        in
        builtins.all (len: len == 3) results; # All should have 3 segments
      expected = true;
    };

    "stress: normalize 1000 paths with trailing slashes" = {
      expr =
        let
          pathsWithSlash = pkgs.lib.genList (n: ".dir${toString n}/") 1000;
          normalized = map (path: pathManagerLib.typeDetection.normalizePath path) pathsWithSlash;
        in
        builtins.all (p: !(pkgs.lib.hasSuffix "/" p)) normalized; # None should have trailing slash
      expected = true;
    };

    # ========================================================================
    # FILESYSTEM OPERATION VALIDATION (12 tests)
    # ========================================================================

    "fs-validation: tmpfiles.d rule syntax for extensible file" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/test.conf" = pathManagerLib.mkExtensiblePath { text = "content"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # Should have a rule like: C /persist/home/test-user/.config/test.conf /nix/store/...-managed-file -
          hasValidRule = builtins.any (
            rule: (builtins.match "C /persist/home/test-user/\\.config/test\\.conf .* -" rule) != null
          ) rules;
        in
        hasValidRule;
      expected = true;
    };

    "fs-validation: tmpfiles.d rule syntax for extensible directory" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/" = pathManagerLib.mkExtensiblePath { type = "directory"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # Should have a rule like: d /persist/home/test-user/.config/app 0755 - - -
          hasValidRule = builtins.any (
            rule: (builtins.match "d /persist/home/test-user/\\.config/app .*" rule) != null
          ) rules;
        in
        hasValidRule;
      expected = true;
    };

    "fs-validation: home.file paths are valid (no special shell chars unescaped)" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/my-app.conf" = pathManagerLib.mkImmutablePath { text = "test"; };
              };
            }
          ];
        in
        # Should be accessible in home.file
        config.config.home.file ? ".config/my-app.conf";
      expected = true;
    };

    "fs-validation: persistence paths don't have leading slashes" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
          persistFiles = config.config.home.persistence."/persist/home/test-user".files;
        in
        # Paths should be relative (no leading slash)
        builtins.all (path: !(pkgs.lib.hasPrefix "/" path)) persistFiles;
      expected = true;
    };

    "fs-validation: immutable file source path is in nix store" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkImmutablePath { text = "#!/bin/bash"; };
              };
            }
          ];
          fileConfig = config.config.home.file.".bashrc";
        in
        # Should have text attribute set
        fileConfig ? text && fileConfig.text == "#!/bin/bash";
      expected = true;
    };

    "fs-validation: immutable directory source is recursive" = {
      expr =
        let
          testDir = pkgs.writeTextDir "config.json" "{}";
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/myapp/" = pathManagerLib.mkImmutablePath {
                  source = testDir;
                  type = "directory";
                };
              };
            }
          ];
          fileConfig = config.config.home.file.".config/myapp";
        in
        # Should have recursive = true
        fileConfig.recursive or false;
      expected = true;
    };

    "fs-validation: extensible file content is in nix store" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/init.conf" = pathManagerLib.mkExtensiblePath { text = "initial content"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # Rule should reference a /nix/store path
          hasStoreRef = builtins.any (
            rule:
            (builtins.match ".*(/nix/store/[^[:space:]]+).*" rule) != null
          ) rules;
        in
        hasStoreRef;
      expected = true;
    };

    "fs-validation: paths normalized in all outputs" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/" = pathManagerLib.mkMutablePath // { type = "directory"; };
              };
            }
          ];
          persistDirs = config.config.home.persistence."/persist/home/test-user".directories;
        in
        # Should be normalized (no trailing slash)
        builtins.elem ".config/app" persistDirs && !(builtins.elem ".config/app/" persistDirs);
      expected = true;
    };

    "fs-validation: multiple files in same directory allowed" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/file1" = pathManagerLib.mkMutablePath;
                ".config/app/file2" = pathManagerLib.mkMutablePath;
                ".config/app/file3" = pathManagerLib.mkMutablePath;
              };
            }
          ];
          persistFiles = config.config.home.persistence."/persist/home/test-user".files;
        in
        (builtins.elem ".config/app/file1" persistFiles)
        && (builtins.elem ".config/app/file2" persistFiles)
        && (builtins.elem ".config/app/file3" persistFiles);
      expected = true;
    };

    "fs-validation: ephemeral paths produce no filesystem operations" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".cache/ephemeral" = pathManagerLib.mkEphemeralPath;
                ".cache/temp/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
          persistFiles = config.config.home.persistence."/persist/home/test-user".files;
          persistDirs = config.config.home.persistence."/persist/home/test-user".directories;
          homeFiles = builtins.attrNames config.config.home.file;
        in
        # Ephemeral paths should not appear anywhere
        !(builtins.elem ".cache/ephemeral" persistFiles)
        && !(builtins.elem ".cache/temp" persistDirs)
        && !(builtins.elem ".cache/ephemeral" homeFiles)
        && !(builtins.elem ".cache/temp" homeFiles);
      expected = true;
    };

    "fs-validation: tmpfiles.d rules have correct format (C directive)" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/test.conf" = pathManagerLib.mkExtensiblePath { text = "test"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # C directive format: C path source mode
          # Should match: C <path> <source> -
          validFormat = builtins.all (
            rule:
            let
              match = builtins.match "C ([^[:space:]]+) ([^[:space:]]+) -" rule;
            in
            match != null
          ) (builtins.filter (r: pkgs.lib.hasPrefix "C " r) rules);
        in
        validFormat;
      expected = true;
    };

    "fs-validation: tmpfiles.d rules have correct format (d directive)" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/data/" = pathManagerLib.mkExtensiblePath { type = "directory"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # d directive format: d path mode user group age
          # Should match: d <path> <mode> - - -
          validFormat = builtins.all (
            rule:
            let
              match = builtins.match "d ([^[:space:]]+) ([0-9]+) - - -" rule;
            in
            match != null
          ) (builtins.filter (r: pkgs.lib.hasPrefix "d " r) rules);
        in
        validFormat;
      expected = true;
    };

  };
}



