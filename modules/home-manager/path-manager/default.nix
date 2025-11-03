# path-manager Home Manager module
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.home.pathManager;

  # Import path-manager library for type detection and validation
  pathManagerLib = import ../../../lib { inherit lib; };

in
{
  options.home.pathManager =
    with lib.types;
    mkOption {
      type = attrsOf (submodule {
        options = {
          state = mkOption {
            type = enum [
              "immutable"
              "ephemeral"
              "mutable"
              "extensible"
            ];
            description = "The desired state of the path.";
          };
          source = mkOption {
            type = nullOr path;
            default = null;
            description = "The source file/directory for 'immutable' and 'extensible' states.";
          };
          text = mkOption {
            type = nullOr str;
            default = null;
            description = "The text content for 'immutable' and 'extensible' states (files only).";
          };
          type = mkOption {
            type = nullOr (enum [ "file" "directory" ]);
            default = null;
            description = ''
              Explicitly specify whether this path is a file or directory.
              If not specified, type will be auto-detected based on:
              - Trailing slash (/) → directory
              - source pointing to directory → directory
              - No source/text + (mutable|ephemeral) → directory
              - Has source or text → file
              - Default → file
            '';
          };
        };
      });
      default = { };
      description = "A declarative way to manage paths in an impermanence setup.";
    };

  config =
    let
      # Classify each path as file or directory
      classifiedPaths = mapAttrs (
        path: decl:
        let
          detectedType = pathManagerLib.typeDetection.inferPathType {
            inherit path;
            type = decl.type;
            source = decl.source;
            text = decl.text;
            state = decl.state;
          };
          normalPath = pathManagerLib.typeDetection.normalizePath path;
        in
        {
          inherit (decl) state source text;
          type = decl.type;
          detectedType = detectedType;
          normalPath = normalPath;
        }
      ) cfg;

      # Separate files from directories
      files = filterAttrs (_: v: v.detectedType == "file") classifiedPaths;
      directories = filterAttrs (_: v: v.detectedType == "directory") classifiedPaths;

      # Immutable files and directories
      immutableFiles = filterAttrs (_: v: v.state == "immutable") files;
      immutableDirs = filterAttrs (_: v: v.state == "immutable") directories;

      # Persisted paths (mutable + extensible)
      persistedFiles = filterAttrs (_: v: v.state == "mutable" || v.state == "extensible") files;
      persistedDirs = filterAttrs (_: v: v.state == "mutable" || v.state == "extensible") directories;

      # Extensible paths needing initial content
      extensibleFiles = filterAttrs (_: v: v.state == "extensible") files;
      extensibleDirs = filterAttrs (_: v: v.state == "extensible") directories;

    in
    {
      # Immutable files: add to home.file with mkForce
      home.file = lib.mkMerge (
        lib.mapAttrsToList (
          path: decl:
          {
            ${decl.normalPath} = lib.mkForce {
              source = decl.source;
              text = decl.text;
            };
          }
        ) immutableFiles
        ++
        # Immutable directories: add to home.file as recursive
        lib.mapAttrsToList (
          path: decl:
          {
            ${decl.normalPath} = lib.mkForce {
              source = decl.source;
              recursive = true;
            };
          }
        ) immutableDirs
      );

      # Persisted files: add to home.persistence.files
      # Persisted directories: add to home.persistence.directories
      home.persistence."/persist/home/${config.home.username}" = {
        files = map (v: v.normalPath) (attrValues persistedFiles);
        directories = map (v: v.normalPath) (attrValues persistedDirs);
      };

      # Platform-specific logic for extensible paths (initial content)
      systemd.tmpfiles.rules = lib.mkIf pkgs.stdenv.isLinux (
        lib.filter (rule: rule != null) (
          # Extensible files
          (lib.mapAttrsToList (
            path: decl:
            let
              content =
                if decl.source != null then decl.source else (pkgs.writeText "managed-file" decl.text);
            in
            "C /persist/home/${config.home.username}/${decl.normalPath} ${content} -"
          ) extensibleFiles)
          ++
          # Extensible directories
          (lib.mapAttrsToList (
            path: decl:
            if decl.source != null then
              "C /persist/home/${config.home.username}/${decl.normalPath} ${decl.source} -"
            else
              # For directories without source, just create empty dir
              "d /persist/home/${config.home.username}/${decl.normalPath} 0755 - - -"
          ) extensibleDirs)
        )
      );

      # TODO: Implement nix-darwin equivalent using launchd
      # See: https://www.launchd.info/
      # And: https://nix-community.github.io/home-manager/options.html#opt-launchd.agents
      launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
        # ... placeholder for launchd agent ...
      };

      # Note: Full conflict detection with parent-child relationship analysis
      # is not feasible in the HM module due to module system evaluation order.
      # For comprehensive validation, use the NixOS module which has system-level visibility.
      #
      # We can perform basic same-path conflict detection here as best-effort.
    };
}
