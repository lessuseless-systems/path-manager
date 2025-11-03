# path-manager.nix
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.home.pathManager;
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
            description = "The desired state of the file.";
          };
          source = mkOption {
            type = nullOr path;
            default = null;
            description = "The source file for 'immutable' and 'extensible' states.";
          };
          text = mkOption {
            type = nullOr str;
            default = null;
            description = "The text content for 'immutable' and 'extensible' states.";
          };
        };
      });
      default = { };
      description = "A declarative way to manage files in an impermanence setup.";
    };

  config = {
    # Use mkForce on individual paths to ensure pathManager takes precedence
    home.file = lib.mkMerge (
      # Immutable paths: override with content
      (lib.mapAttrsToList (
        path: file:
        lib.mkIf (file.state == "immutable") {
          ${path} = lib.mkForce {
            source = file.source;
            text = file.text;
          };
        }
      ) cfg)
      ++
      # Ephemeral paths: explicitly remove from home.file with mkForce
      (lib.mapAttrsToList (
        path: file:
        lib.mkIf (file.state == "ephemeral") {
          ${path} = lib.mkForce null;
        }
      ) cfg)
    );

    # Add to persistence list (duplicates are harmless, lists concatenate)
    home.persistence."/persist/home/${config.home.username}" = {
      files = lib.filter (path: path != null) (
        lib.mapAttrsToList (
          path: file: if (file.state == "mutable" || file.state == "extensible") then path else null
        ) cfg
      );
    };

    # Platform-specific logic for initial content
    systemd.tmpfiles.rules = lib.mkIf pkgs.stdenv.isLinux (
      lib.filter (rule: rule != null) (
        lib.mapAttrsToList (
          path: file:
          if file.state == "extensible" then
            (
              let
                content = if file.source != null then file.source else (pkgs.writeText "managed-file" file.text);
              in
              "C /persist/home/${config.home.username}/${path} ${content} -"
            )
          else
            null
        ) cfg
      )
    );

    # TODO: Implement nix-darwin equivalent using launchd
    # See: https://www.launchd.info/
    # And: https://nix-community.github.io/home-manager/options.html#opt-launchd.agents
    launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
      # ... placeholder for launchd agent ...
    };
  };
}
