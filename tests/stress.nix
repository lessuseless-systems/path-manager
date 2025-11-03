# Stress Tests - 1000+ Paths

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

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

  };
}
