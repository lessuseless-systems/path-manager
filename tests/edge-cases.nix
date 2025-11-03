# Edge Cases with Empty/Null Values Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

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

  };
}
