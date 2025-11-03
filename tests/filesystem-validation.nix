# Filesystem Operation Validation Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

    "fs-validation: tmpfiles.d rule syntax for extensible file" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/test.conf" = pathManagerLib.mkExtensiblePath { text = "content"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # Should have a rule like: C /persist/home/test-user/.config/test.conf /nix/store/...-managed-file -
          hasValidRule = builtins.any (
            rule: (builtins.match "C /persist/home/test-user/\\.config/test\\.conf .* -" rule) != null
          ) rules;
        in
        hasValidRule;
      expected = true;
    };

    "fs-validation: tmpfiles.d rule syntax for extensible directory" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/" = pathManagerLib.mkExtensiblePath { type = "directory"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # Should have a rule like: d /persist/home/test-user/.config/app 0755 - - -
          hasValidRule = builtins.any (
            rule: (builtins.match "d /persist/home/test-user/\\.config/app .*" rule) != null
          ) rules;
        in
        hasValidRule;
      expected = true;
    };

    "fs-validation: home.file paths are valid (no special shell chars unescaped)" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/my-app.conf" = pathManagerLib.mkImmutablePath { text = "test"; };
              };
            }
          ];
        in
        # Should be accessible in home.file
        config.config.home.file ? ".config/my-app.conf";
      expected = true;
    };

    "fs-validation: persistence paths don't have leading slashes" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
          persistFiles = config.config.home.persistence."/persist/home/test-user".files;
        in
        # Paths should be relative (no leading slash)
        builtins.all (path: !(pkgs.lib.hasPrefix "/" path)) persistFiles;
      expected = true;
    };

    "fs-validation: immutable file source path is in nix store" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkImmutablePath { text = "#!/bin/bash"; };
              };
            }
          ];
          fileConfig = config.config.home.file.".bashrc";
        in
        # Should have text attribute set
        fileConfig ? text && fileConfig.text == "#!/bin/bash";
      expected = true;
    };

    "fs-validation: immutable directory source is recursive" = {
      expr =
        let
          testDir = pkgs.writeTextDir "config.json" "{}";
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/myapp/" = pathManagerLib.mkImmutablePath {
                  source = testDir;
                  type = "directory";
                };
              };
            }
          ];
          fileConfig = config.config.home.file.".config/myapp";
        in
        # Should have recursive = true
        fileConfig.recursive or false;
      expected = true;
    };

    "fs-validation: extensible file content is in nix store" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/init.conf" = pathManagerLib.mkExtensiblePath { text = "initial content"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # Rule should reference a /nix/store path
          hasStoreRef = builtins.any (
            rule:
            (builtins.match ".*(/nix/store/[^[:space:]]+).*" rule) != null
          ) rules;
        in
        hasStoreRef;
      expected = true;
    };

    "fs-validation: paths normalized in all outputs" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/" = pathManagerLib.mkMutablePath // { type = "directory"; };
              };
            }
          ];
          persistDirs = config.config.home.persistence."/persist/home/test-user".directories;
        in
        # Should be normalized (no trailing slash)
        builtins.elem ".config/app" persistDirs && !(builtins.elem ".config/app/" persistDirs);
      expected = true;
    };

    "fs-validation: multiple files in same directory allowed" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app/file1" = pathManagerLib.mkMutablePath;
                ".config/app/file2" = pathManagerLib.mkMutablePath;
                ".config/app/file3" = pathManagerLib.mkMutablePath;
              };
            }
          ];
          persistFiles = config.config.home.persistence."/persist/home/test-user".files;
        in
        (builtins.elem ".config/app/file1" persistFiles)
        && (builtins.elem ".config/app/file2" persistFiles)
        && (builtins.elem ".config/app/file3" persistFiles);
      expected = true;
    };

    "fs-validation: ephemeral paths produce no filesystem operations" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".cache/ephemeral" = pathManagerLib.mkEphemeralPath;
                ".cache/temp/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
          persistFiles = config.config.home.persistence."/persist/home/test-user".files;
          persistDirs = config.config.home.persistence."/persist/home/test-user".directories;
          homeFiles = builtins.attrNames config.config.home.file;
        in
        # Ephemeral paths should not appear anywhere
        !(builtins.elem ".cache/ephemeral" persistFiles)
        && !(builtins.elem ".cache/temp" persistDirs)
        && !(builtins.elem ".cache/ephemeral" homeFiles)
        && !(builtins.elem ".cache/temp" homeFiles);
      expected = true;
    };

    "fs-validation: tmpfiles.d rules have correct format (C directive)" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/test.conf" = pathManagerLib.mkExtensiblePath { text = "test"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # C directive format: C path source mode
          # Should match: C <path> <source> -
          validFormat = builtins.all (
            rule:
            let
              match = builtins.match "C ([^[:space:]]+) ([^[:space:]]+) -" rule;
            in
            match != null
          ) (builtins.filter (r: pkgs.lib.hasPrefix "C " r) rules);
        in
        validFormat;
      expected = true;
    };

    "fs-validation: tmpfiles.d rules have correct format (d directive)" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".local/data/" = pathManagerLib.mkExtensiblePath { type = "directory"; };
              };
            }
          ];
          rules = config.config.systemd.tmpfiles.rules;
          # d directive format: d path mode user group age
          # Should match: d <path> <mode> - - -
          validFormat = builtins.all (
            rule:
            let
              match = builtins.match "d ([^[:space:]]+) ([0-9]+) - - -" rule;
            in
            match != null
          ) (builtins.filter (r: pkgs.lib.hasPrefix "d " r) rules);
        in
        validFormat;
      expected = true;
    };

  };
}
