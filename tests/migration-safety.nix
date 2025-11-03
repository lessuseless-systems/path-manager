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
    # Dry-run mode: Default behavior
    "dry-run is enabled by default" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        config.config.home.pathManager.dryRun;
      expected = true;
    };

    # Dry-run mode: Can be disabled
    "dry-run can be disabled explicitly" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                dryRun = false;
                paths = {
                  ".bashrc" = pathManagerLib.mkMutablePath;
                };
              };
            }
          ];
        in
        config.config.home.pathManager.dryRun;
      expected = false;
    };

    # Dry-run mode: Activation script exists when enabled
    "dry-run creates activation script when enabled" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        config.config.home.activation ? pathManagerDryRunCheck;
      expected = true;
    };

    # Dry-run mode: No activation script when disabled
    "dry-run skips activation script when disabled" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                dryRun = false;
                paths = {
                  ".bashrc" = pathManagerLib.mkMutablePath;
                };
              };
            }
          ];
        in
        config.config.home.activation ? pathManagerDryRunCheck;
      expected = false;
    };

    # Dry-run mode: Config still evaluates with mutable paths
    "dry-run config evaluates with mutable paths" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # Just verify config evaluates without error
        config.config.home.homeDirectory != null;
      expected = true;
    };

    # Dry-run mode: Still creates home.file for immutable paths
    "dry-run still declares immutable paths" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkImmutablePath { text = "test"; };
              };
            }
          ];
        in
        config.config.home.file.".bashrc".text;
      expected = "test";
    };

    # Dry-run mode: Environment variable override support
    "dry-run respects PATHMANAGER_APPLY env var" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
          # The activation script should check for PATHMANAGER_APPLY=1
          activationScript = config.config.home.activation.pathManagerDryRunCheck.data or "";
        in
        # Check that the script references the environment variable
        builtins.match ".*PATHMANAGER_APPLY.*" activationScript != null;
      expected = true;
    };

    # Dry-run mode: Activation script contains dry-run warning
    "dry-run activation script shows warning message" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
            }
          ];
          activationScript = config.config.home.activation.pathManagerDryRunCheck.data or "";
        in
        # Should mention dry-run mode
        builtins.match ".*[Dd]ry.run.*" activationScript != null;
      expected = true;
    };

    # Dry-run mode: Works with custom persistence root
    "dry-run works with custom persistence root" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager = {
                persistenceRoot = "/nix/persist/home/test-user";
                paths = {
                  ".bashrc" = pathManagerLib.mkMutablePath;
                };
              };
            }
          ];
        in
        # Verify custom root is set correctly
        config.config.home.pathManager.persistenceRoot;
      expected = "/nix/persist/home/test-user";
    };

    # Dry-run mode: Multiple paths handled correctly
    "dry-run handles multiple paths" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
                ".vimrc" = pathManagerLib.mkMutablePath;
                ".config/nvim/" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # Verify config evaluates with multiple paths
        builtins.length (builtins.attrNames config.config.home.pathManager.paths);
      expected = 3;
    };
  };
}
