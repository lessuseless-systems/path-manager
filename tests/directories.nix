# Directory Handling Tests
# Tests for directory-specific behaviors and persistence

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {
    "directory: mutable directory → adds to persistence.directories" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/state/" = pathManagerLib.mkMutablePath // { type = "directory"; };
              };
            }
          ];
        in
        builtins.elem ".local/state" config.config.home.persistence."/persist/home/test-user".directories;
      expected = true;
    };

    "directory: mutable file → adds to persistence.files" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/state/file.db" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem ".local/state/file.db" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "directory: extensible directory → adds to persistence.directories" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/" = pathManagerLib.mkExtensiblePath { text = "init"; };
              };
            }
          ];
        in
        builtins.elem ".config/app" config.config.home.persistence."/persist/home/test-user".directories;
      expected = true;
    };

    "directory: immutable directory with source → adds to home.file as recursive" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/myapp/" = pathManagerLib.mkImmutablePath {
                  source = pkgs.writeTextDir "config.json" "{}";
                  type = "directory";
                };
              };
            }
          ];
        in
        config.config.home.file.".config/myapp".recursive or false;
      expected = true;
    };

    "directory: ephemeral directory → not in persistence" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".cache/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        builtins.elem ".cache" config.config.home.persistence."/persist/home/test-user".directories;
      expected = false;
    };

    "directory: ephemeral directory → not in home.file" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".cache/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        config.config.home.file ? ".cache";
      expected = false;
    };

    "directory: extensible directory → creates tmpfiles.d rule" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/data/" = pathManagerLib.mkExtensiblePath { type = "directory"; };
              };
            }
          ];
        in
        builtins.any (
          rule: builtins.match "d /persist/home/test-user/\\.local/data .*" rule != null
        ) config.config.systemd.tmpfiles.rules;
      expected = true;
    };

    "directory: trailing slash auto-detected as directory and persisted" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".mozilla/" = pathManagerLib.mkMutablePath; # auto-detected as directory
              };
            }
          ];
        in
        builtins.elem ".mozilla" config.config.home.persistence."/persist/home/test-user".directories;
      expected = true;
    };
  };
}
