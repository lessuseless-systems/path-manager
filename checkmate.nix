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

    # Precedence Tests - verify pathManager overrides conflicting declarations

    "test precedence: immutable overrides home.file" = {
      expr =
        let
          config = createTestConfig [
            {
              # Conflicting declaration - home.file sets one value
              home.file."/test-conflict" = {
                text = "from home.file";
              };
              # pathManager should override with mkForce
              home.pathManager = {
                "/test-conflict" = pathManagerLib.mkImmutablePath { text = "from pathManager"; };
              };
            }
          ];
        in
        config.config.home.file."/test-conflict".text;
      expected = "from pathManager";
    };

    "test precedence: mutable with existing persistence" = {
      expr =
        let
          config = createTestConfig [
            {
              # Declare path in both home.persistence and pathManager
              home.persistence."/persist/home/test-user".files = [ "/test-persist-conflict" ];
              home.pathManager = {
                "/test-persist-conflict" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # Should not error, and path should be in the list (duplicates are OK with list concatenation)
        builtins.elem "/test-persist-conflict" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "test precedence: extensible with existing persistence" = {
      expr =
        let
          config = createTestConfig [
            {
              # Declare path in both home.persistence and pathManager
              home.persistence."/persist/home/test-user".files = [ ".config/app.conf" ];
              home.pathManager = {
                ".config/app.conf" = pathManagerLib.mkExtensiblePath { text = "initial"; };
              };
            }
          ];
        in
        # Should not error, path should be in the list (duplicates are OK with list concatenation)
        builtins.elem ".config/app.conf" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "test precedence: multiple immutable conflicts" = {
      expr =
        let
          config = createTestConfig [
            {
              # Multiple conflicting home.file declarations
              home.file."/conflict1" = { text = "old1"; };
              home.file."/conflict2" = { text = "old2"; };

              # pathManager should override both
              home.pathManager = {
                "/conflict1" = pathManagerLib.mkImmutablePath { text = "new1"; };
                "/conflict2" = pathManagerLib.mkImmutablePath { text = "new2"; };
              };
            }
          ];
        in
        config.config.home.file."/conflict1".text == "new1" && config.config.home.file."/conflict2".text == "new2";
      expected = true;
    };

    "test precedence: ephemeral doesn't add to home.file" = {
      expr =
        let
          config = createTestConfig [
            {
              # pathManager marks path as ephemeral
              home.pathManager = {
                "/ephemeral-test" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        # ephemeral paths should NOT appear in home.file
        config.config.home.file ? "/ephemeral-test";
      expected = false;
    };

    # Validation Tests - enforce single source of truth

    "test validation: mutable rejects home.file conflict" = {
      expr =
        let
          # This should fail assertion - mutable + home.file conflict
          result = builtins.tryEval (
            createTestConfig [
              {
                home.file."/test-conflict" = { text = "from home.file"; };
                home.pathManager = {
                  "/test-conflict" = pathManagerLib.mkMutablePath;
                };
              }
            ]
          );
        in
        result.success;
      expected = false;
    };

    "test validation: ephemeral rejects home.file conflict" = {
      expr =
        let
          # This should fail assertion - ephemeral + home.file conflict
          result = builtins.tryEval (
            createTestConfig [
              {
                home.file."/test-ephemeral" = { text = "from home.file"; };
                home.pathManager = {
                  "/test-ephemeral" = pathManagerLib.mkEphemeralPath;
                };
              }
            ]
          );
        in
        result.success;
      expected = false;
    };

    "test validation: extensible rejects home.file conflict" = {
      expr =
        let
          # This should fail assertion - extensible + home.file conflict
          result = builtins.tryEval (
            createTestConfig [
              {
                home.file."/test-extensible" = { text = "from home.file"; };
                home.pathManager = {
                  "/test-extensible" = pathManagerLib.mkExtensiblePath { text = "initial"; };
                };
              }
            ]
          );
        in
        result.success;
      expected = false;
    };

    "test validation: immutable allows home.file override" = {
      expr =
        let
          # This should succeed - immutable is allowed to override home.file
          result = builtins.tryEval (
            createTestConfig [
              {
                home.file."/test-override" = { text = "old value"; };
                home.pathManager = {
                  "/test-override" = pathManagerLib.mkImmutablePath { text = "new value"; };
                };
              }
            ]
          );
        in
        result.success && result.value.config.home.file."/test-override".text == "new value";
      expected = true;
    };
  };
}
