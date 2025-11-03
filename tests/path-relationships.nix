# Path Relationship Utility Tests
# Tests for path manipulation and hierarchy detection utilities

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {
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
  };
}
