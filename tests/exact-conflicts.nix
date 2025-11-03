# Exact Conflict Detection Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {
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
  };
}
