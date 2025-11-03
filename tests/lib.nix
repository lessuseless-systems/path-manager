# Shared test infrastructure for path-manager tests
# Used by all test category modules to avoid duplication

{ inputs }:

let
  self = inputs.target;
  home-manager = inputs.target.inputs.home-manager;
  pkgs = import inputs.target.inputs.nixpkgs { system = "x86_64-linux"; };
  pathManagerLib = self.lib;

  # Create a test home-manager configuration with common setup
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
  inherit pkgs pathManagerLib createTestConfig;
}
