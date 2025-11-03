# Hierarchical Conflict Detection Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {
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

  };
}
