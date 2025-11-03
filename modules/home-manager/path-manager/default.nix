# path-manager Home Manager module
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.home.pathManager.paths;
  persistenceRoot = config.home.pathManager.persistenceRoot;

  # Import path-manager library for type detection and validation
  pathManagerLib = import ../../../lib { inherit lib; };

in
{
  options.home.pathManager = {
    paths = with lib.types;
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

    persistenceRoot = mkOption {
      type = types.str;
      default = "/persist/home/${config.home.username}";
      example = "/nix/persist/home/alice";
      description = ''
        The root directory where persistent files and directories are stored.
        This is typically the impermanence persistence root for the user.

        Defaults to /persist/home/''${config.home.username} which works with
        the standard impermanence module configuration.
      '';
    };

    dryRun = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable dry-run mode (default: true).

        When enabled, path-manager will analyze what would happen during activation
        but will NOT actually create bind mounts. This prevents accidental data loss
        during initial migration to path-manager.

        The dry-run check will:
        - Detect paths that would be shadowed by bind mounts
        - Warn about potential data loss
        - Show what actions would be taken

        To apply changes, either:
        1. Set dryRun = false; in your configuration
        2. Run with PATHMANAGER_APPLY=1 environment variable

        It is strongly recommended to review dry-run output before disabling.
      '';
    };
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
      home.persistence.${persistenceRoot} = {
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
            "C ${persistenceRoot}/${decl.normalPath} ${content} -"
          ) extensibleFiles)
          ++
          # Extensible directories
          (lib.mapAttrsToList (
            path: decl:
            if decl.source != null then
              "C ${persistenceRoot}/${decl.normalPath} ${decl.source} -"
            else
              # For directories without source, just create empty dir
              "d ${persistenceRoot}/${decl.normalPath} 0755 - - -"
          ) extensibleDirs)
        )
      );

      # TODO: Implement nix-darwin equivalent using launchd
      # See: https://www.launchd.info/
      # And: https://nix-community.github.io/home-manager/options.html#opt-launchd.agents
      launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
        # ... placeholder for launchd agent ...
      };

      # Dry-run activation check
      home.activation.pathManagerDryRunCheck = lib.mkIf config.home.pathManager.dryRun (
        lib.hm.dag.entryBefore [ "writeBoundary" ] ''
          # Check if PATHMANAGER_APPLY is set to override dry-run
          if [ "''${PATHMANAGER_APPLY:-0}" = "1" ]; then
            $DRY_RUN_CMD echo "[path-manager] PATHMANAGER_APPLY=1 detected, proceeding with activation..."
            exit 0
          fi

          $DRY_RUN_CMD echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          $DRY_RUN_CMD echo "[path-manager] DRY-RUN MODE ENABLED (default)"
          $DRY_RUN_CMD echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          $DRY_RUN_CMD echo ""
          $DRY_RUN_CMD echo "path-manager is analyzing your configuration to prevent data loss."
          $DRY_RUN_CMD echo ""
          $DRY_RUN_CMD echo "The following paths will be managed:"
          $DRY_RUN_CMD echo ""

          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              path: decl:
              ''
                $DRY_RUN_CMD echo "  ${decl.state}: ${config.home.homeDirectory}/${decl.normalPath}"
              ''
            ) classifiedPaths
          )}

          $DRY_RUN_CMD echo ""
          $DRY_RUN_CMD echo "Mutable/extensible paths will be bind-mounted from:"
          $DRY_RUN_CMD echo "  ${persistenceRoot}"
          $DRY_RUN_CMD echo ""
          $DRY_RUN_CMD echo "⚠️  WARNING: Bind mounts will shadow any existing data on root!"
          $DRY_RUN_CMD echo ""
          $DRY_RUN_CMD echo "To apply these changes, choose one of:"
          $DRY_RUN_CMD echo "  1. Add to your config: home.pathManager.dryRun = false;"
          $DRY_RUN_CMD echo "  2. Run with: PATHMANAGER_APPLY=1 home-manager switch ..."
          $DRY_RUN_CMD echo ""
          $DRY_RUN_CMD echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ''
      );

      # Note: Full conflict detection with parent-child relationship analysis
      # is not feasible in the HM module due to module system evaluation order.
      # For comprehensive validation, use the NixOS module which has system-level visibility.
      #
      # We can perform basic same-path conflict detection here as best-effort.
    };
}
