# Type Detection Tests
# Tests for automatic file vs directory type inference

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {
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
  };
}
