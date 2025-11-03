# NixOS module for path-manager
# Provides system-level conflict detection and orchestration with full recursive tree analysis
#
# This module operates at the NixOS level where it can see:
# - home-manager.users.<user>.home.file
# - home-manager.users.<user>.home.persistence.*.files
# - home-manager.users.<user>.home.persistence.*.directories
# - environment.persistence (future)
#
# And detect/resolve conflicts between them with comprehensive parent-child relationship analysis.

{ config, lib, ... }:

with lib;

let
  cfg = config.pathManager;

  # Import path-manager library for type detection and validation
  pathManagerLib = import ../../lib { inherit lib; };

  # Define the path state submodule (same as HM module but with type field)
  pathStateModule = types.submodule {
    options = {
      state = mkOption {
        type = types.enum [
          "immutable"
          "ephemeral"
          "mutable"
          "extensible"
        ];
        description = "The desired state of the path.";
      };
      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "The source file/directory for 'immutable' and 'extensible' states.";
      };
      text = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The text content for 'immutable' and 'extensible' states (files only).";
      };
      type = mkOption {
        type = types.nullOr (types.enum [ "file" "directory" ]);
        default = null;
        description = ''
          Explicitly specify whether this path is a file or directory.
          If not specified, type will be auto-detected.
        '';
      };
    };
  };

  # Collect all paths from home.file for a user
  collectHomeFilePaths =
    user:
    let
      homeFileConfig = config.home-manager.users.${user}.home.file or { };
    in
    attrNames homeFileConfig;

  # Collect all paths from home.persistence.*.files for a user
  collectPersistenceFiles =
    user:
    let
      persistenceConfig = config.home-manager.users.${user}.home.persistence or { };
      allFiles = flatten (
        mapAttrsToList (_persistRoot: persistCfg: persistCfg.files or [ ]) persistenceConfig
      );
    in
    unique allFiles;

  # Collect all paths from home.persistence.*.directories for a user
  collectPersistenceDirectories =
    user:
    let
      persistenceConfig = config.home-manager.users.${user}.home.persistence or { };
      allDirs = flatten (
        mapAttrsToList (_persistRoot: persistCfg: persistCfg.directories or [ ]) persistenceConfig
      );
    in
    unique allDirs;

  # Generate comprehensive conflict detection assertions for a user
  # Uses shared validation library for full recursive tree analysis
  userAssertions =
    user: userConfig:
    let
      # Collect all paths from various sources
      pathManagerDecls = userConfig;
      homeFilePaths = collectHomeFilePaths user;
      persistenceFiles = collectPersistenceFiles user;
      persistenceDirs = collectPersistenceDirectories user;

      # Run exact path conflict detection
      exactConflicts = pathManagerLib.validation.detectExactConflicts {
        inherit pathManagerDecls homeFilePaths persistenceFiles persistenceDirs;
        warnOnRedundant = true;
      };

      # Run full recursive hierarchical conflict detection
      hierarchicalConflicts = pathManagerLib.validation.detectHierarchicalConflicts {
        inherit pathManagerDecls homeFilePaths persistenceFiles persistenceDirs;
      };

      # Enhance error messages with user context
      enhanceMessage =
        assertion:
        assertion
        // {
          message = ''
            [User: ${user}]

            ${assertion.message}
          '';
        };

    in
    map enhanceMessage (exactConflicts ++ hierarchicalConflicts);

in
{
  options.pathManager = {
    enable = mkEnableOption "path-manager system-level orchestration with full conflict detection";

    users = mkOption {
      type = types.attrsOf (types.attrsOf pathStateModule);
      default = { };
      description = ''
        Per-user path management declarations.

        This operates at the NixOS level and provides comprehensive conflict detection including:
        - Exact path conflicts (same path in multiple sources)
        - Hierarchical conflicts (parent-child relationships)
        - Full recursive tree analysis across all path declarations

        Example:
          pathManager.users.alice = {
            ".bashrc" = { state = "immutable"; text = "..."; };
            ".local/state/db" = { state = "mutable"; };
            ".config/app/" = { state = "mutable"; type = "directory"; };
          };
      '';
      example = literalExpression ''
        {
          alice = {
            ".bashrc" = { state = "immutable"; source = ./bashrc; };
            ".config/chromium/Default" = { state = "mutable"; type = "directory"; };
            ".cache/" = { state = "ephemeral"; };
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # Generate comprehensive assertions for all users
    # Includes both exact path conflicts and full hierarchical (parent-child) analysis
    assertions = flatten (
      mapAttrsToList (user: userConfig: userAssertions user userConfig) cfg.users
    );

    # Apply pathManager configuration to home-manager for each user
    # The actual path management is delegated to the HM module
    home-manager.users = mapAttrs (
      _user: userConfig:
      {
        home.pathManager = userConfig;
      }
    ) cfg.users;

    # Note: The actual file/persistence management is delegated to the HM module.
    # This NixOS module provides:
    # 1. System-level visibility for comprehensive conflict detection
    # 2. Full recursive tree analysis (parent-child relationships)
    # 3. Detailed error messages with resolution guidance
  };
}
