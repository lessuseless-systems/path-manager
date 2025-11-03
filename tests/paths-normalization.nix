# Path Normalization Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

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

  };
}
