# Three-Way Conflict Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

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

  };
}
