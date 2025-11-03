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
        # Should not error, and path should be in the list
        # Count occurrences to verify no duplication
        builtins.length (
          builtins.filter (p: p == "/test-persist-conflict") config.config.home.persistence."/persist/home/test-user".files
        );
      expected = 1;
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
        # Should not error, verify exactly one occurrence
        builtins.length (
          builtins.filter (p: p == ".config/app.conf") config.config.home.persistence."/persist/home/test-user".files
        );
      expected = 1;
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

    "test precedence: ephemeral ignores home.file" = {
      expr =
        let
          config = createTestConfig [
            {
              # Declare in home.file
              home.file."/ephemeral-conflict" = { text = "should be ignored"; };

              # pathManager marks it as ephemeral (should not appear in home.file)
              home.pathManager = {
                "/ephemeral-conflict" = pathManagerLib.mkEphemeralPath;
              };
            }
          ];
        in
        # ephemeral should result in path NOT being in home.file
        # Even though we declared it there, pathManager should override
        config.config.home.file ? "/ephemeral-conflict";
      expected = false;
    };
  };
}
