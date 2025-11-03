{ inputs, ... }:
let
  self = inputs.target;
  home-manager = inputs.target.inputs.home-manager;
  pkgs = import inputs.target.inputs.nixpkgs { system = "x86_64-linux"; };

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
                "/test-file" = {
                  state = "immutable";
                  text = "hello";
                };
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
                "/test-ephemeral-file" = {
                  state = "ephemeral";
                };
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
                "/test-mutable-file" = {
                  state = "mutable";
                };
              };
            }
          ];
        in
        config.config.home.persistence."/persist/home/test-user".files ? "/test-mutable-file";
      expected = true;
    };
  };
}
