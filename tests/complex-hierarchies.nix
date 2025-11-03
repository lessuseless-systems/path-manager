# Complex Hierarchical Scenarios Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

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

  };
}
