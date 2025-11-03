# NixOS module for path-manager
# Provides system-level conflict detection and orchestration
#
# This module operates at the NixOS level where it can see both:
# - home-manager.users.<user>.home.file
# - home-manager.users.<user>.home.persistence
# - environment.persistence
#
# And detect/resolve conflicts between them.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.pathManager;

  # Import the library for helper functions
  pathManagerLib = import ./lib { inherit lib; };

  # Define the path state submodule (same as HM module)
  pathStateModule = types.submodule {
    options = {
      state = mkOption {
        type = types.enum [ "immutable" "ephemeral" "mutable" "extensible" ];
        description = "The desired state of the path.";
      };
      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "The source file for 'immutable' and 'extensible' states.";
      };
      text = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The text content for 'immutable' and 'extensible' states.";
      };
    };
  };

  # Check if a path is declared in home.file for a user
  isInHomeFile = user: path:
    config.home-manager.users.${user}.home.file ? ${path};

  # Check if a path is declared in home.persistence for a user
  isInHomePersistence = user: path:
    let
      persistencePaths = attrNames (config.home-manager.users.${user}.home.persistence or {});
    in
    any (persistPath:
      let
        files = config.home-manager.users.${user}.home.persistence.${persistPath}.files or [];
      in
      elem path files
    ) persistencePaths;

  # Generate conflict detection assertions for a user
  userAssertions = user: userConfig:
    flatten (
      mapAttrsToList (path: file:
        let
          inHomeFile = isInHomeFile user path;
          inHomePersistence = isInHomePersistence user path;

          # Determine expected state based on pathManager declaration
          expectedInHomeFile = file.state == "immutable";
          expectedInPersistence = file.state == "mutable" || file.state == "extensible";

        in
        [
          # For non-immutable states, warn if also in home.file
          (optionalAttrs (file.state != "immutable" && inHomeFile) {
            assertion = false;
            message = ''
              Path '${path}' for user '${user}' has conflicting declarations:

              - Declared in pathManager as: ${file.state}
              - Also declared in: home-manager.users.${user}.home.file

              pathManager is the single source of truth. Please remove the home.file declaration.

              Correct configuration:
                pathManager.users.${user}."${path}" = ${
                  if file.state == "ephemeral" then "mkEphemeralPath;"
                  else if file.state == "mutable" then "mkMutablePath;"
                  else "mkExtensiblePath { ... };"
                }
            '';
          })

          # Check for redundant persistence declarations
          (optionalAttrs (expectedInPersistence && inHomePersistence) {
            assertion = true;  # Just a warning, not an error
            message = ''
              Note: Path '${path}' for user '${user}' is declared in both:
              - pathManager (${file.state})
              - home.persistence

              This is redundant but harmless. pathManager will handle persistence.
            '';
          })
        ]
      ) userConfig
    );

in
{
  options.pathManager = {
    enable = mkEnableOption "path-manager system-level orchestration";

    users = mkOption {
      type = types.attrsOf (types.attrsOf pathStateModule);
      default = {};
      description = ''
        Per-user path management declarations.

        This operates at the NixOS level and can detect conflicts between
        home-manager and impermanence declarations.

        Example:
          pathManager.users.alice = {
            ".bashrc" = { state = "immutable"; text = "..."; };
            ".local/state/db" = { state = "mutable"; };
          };
      '';
      example = literalExpression ''
        {
          alice = {
            ".bashrc" = { state = "immutable"; source = ./bashrc; };
            ".config/chromium/Default" = { state = "mutable"; };
            ".cache" = { state = "ephemeral"; };
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # Generate assertions for all users
    assertions = flatten (
      mapAttrsToList (user: userConfig:
        userAssertions user userConfig
      ) cfg.users
    );

    # Apply pathManager configuration to home-manager for each user
    home-manager.users = mapAttrs (user: userConfig:
      let
        # Convert pathManager declarations to home-manager config
        hmConfig = {
          home.pathManager = userConfig;
        };
      in
      hmConfig
    ) cfg.users;

    # Note: The actual file/persistence management is delegated to the HM module
    # This NixOS module just provides conflict detection and validation
  };
}
