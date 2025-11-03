{ inputs, ... }:
let
  self = inputs.target;
  home-manager = inputs.target.inputs.home-manager;
  pkgs = import inputs.target.inputs.nixpkgs { system = "x86_64-linux"; };
  pathManagerLib = self.lib;

  createTestConfig =
    modules:
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs;
      modules = [
        self.flakeModule
        inputs.target.inputs.impermanence.homeManagerModules.impermanence
        {
          # Fake systemd module for testing
          options.systemd.tmpfiles.rules = pkgs.lib.mkOption {
            type = pkgs.lib.types.listOf pkgs.lib.types.str;
            default = [ ];
          };
        }
        {
          home.stateVersion = "22.11";
          home.username = "test-user";
          home.homeDirectory = "/home/test-user";
        }
      ] ++ modules;
    };

in
{
  perSystem.nix-unit.tests = {
    "test immutable" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                "/test-file" = pathManagerLib.mkImmutablePath { text = "hello"; };
              };
            }
          ];
        in
        config.config.home.file."/test-file".text;
      expected = "hello";
    };

    "test ephemeral" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                "/test-ephemeral-file" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        config.config.home.file ? "/test-ephemeral-file";
      expected = false;
    };

    "test mutable" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                "/test-mutable-file" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem "/test-mutable-file" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "test extensible - persisted" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                ".config/test.conf" = pathManagerLib.mkExtensiblePath { text = "initial content"; };
              };
            }
          ];
        in
        builtins.elem ".config/test.conf" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "test extensible - tmpfiles rule" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                ".config/test.conf" = pathManagerLib.mkExtensiblePath { text = "initial content"; };
              };
            }
          ];
        in
        builtins.any (rule: builtins.match "C /persist/home/test-user/\\.config/test\\.conf.*" rule != null) config.config.systemd.tmpfiles.rules;
      expected = true;
    };
  };
}
