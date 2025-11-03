# Integration Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

    "integration: complex real-world chromium cookies scenario" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                # Persist the entire Default profile directory
                ".config/chromium/Default/" = pathManagerLib.mkMutablePath // { type = "directory"; };
                # Initialize cookies if they don't exist
                ".config/chromium/Default/Cookies" = pathManagerLib.mkExtensiblePath {
                  text = "# Initial cookies DB";
                };
              };
            }
          ];
        in
        # Both should be in persistence
        builtins.elem ".config/chromium/Default"
          config.config.home.persistence."/persist/home/test-user".directories
        && builtins.elem ".config/chromium/Default/Cookies"
          config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "integration: mixed states in same directory tree" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                # Immutable config
                ".config/app/config.json" = pathManagerLib.mkImmutablePath { text = "{}"; };
                # Mutable data in same tree
                ".config/app/data/" = pathManagerLib.mkMutablePath // { type = "directory"; };
                # Ephemeral cache in same tree
                ".config/app/cache/" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        # Immutable in home.file
        (config.config.home.file ? ".config/app/config.json")
        # Mutable in persistence
        && (
          builtins.elem ".config/app/data" config.config.home.persistence."/persist/home/test-user".directories
        )
        # Ephemeral not in persistence or home.file
        && !(config.config.home.file ? ".config/app/cache")
        && !(
          builtins.elem ".config/app/cache" config.config.home.persistence."/persist/home/test-user".directories
        );
      expected = true;
    };

    "integration: all four states working together" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                # Immutable
                ".bashrc" = pathManagerLib.mkImmutablePath { text = "#!/bin/bash"; };
                # Ephemeral
                ".cache/temp/" = pathManagerLib.mkEphemeralPath;
                # Mutable
                ".local/state/app.db" = pathManagerLib.mkMutablePath;
                # Extensible
                ".config/settings.json" = pathManagerLib.mkExtensiblePath { text = "{}"; };
              };
            }
          ];
        in
        # Verify each state
        (config.config.home.file ? ".bashrc") # immutable
        && !(config.config.home.file ? ".cache/temp") # ephemeral
        && (
          builtins.elem ".local/state/app.db" config.config.home.persistence."/persist/home/test-user".files
        ) # mutable
        && (
          builtins.elem ".config/settings.json" config.config.home.persistence."/persist/home/test-user".files
        ); # extensible
      expected = true;
    };

    # ADVANCED EDGE CASES (32+ tests)

  };
}
