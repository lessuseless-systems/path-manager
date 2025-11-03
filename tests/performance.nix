# Performance Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

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

  };
}
