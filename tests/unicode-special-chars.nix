# Unicode and Special Characters Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

    "unicode: path with emoji persists correctly" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/🎨-theme.json" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem ".config/🎨-theme.json" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "unicode: path with chinese characters" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/配置.conf" = pathManagerLib.mkImmutablePath { text = "test"; };
              };
            }
          ];
        in
        config.config.home.file ? ".config/配置.conf";
      expected = true;
    };

    "special-chars: path with spaces detected as directory" = {
      expr =
        let
          detectedType = pathManagerLib.typeDetection.inferPathType {
            path = ".config/my app/";
            type = null;
            source = null;
            text = null;
            state = "mutable";
          };
        in
        detectedType;
      expected = "directory";
    };

    "special-chars: path with dots and dashes" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".config/app-v1.2.3.conf" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        builtins.elem ".config/app-v1.2.3.conf" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "special-chars: normalize path handles unicode" = {
      expr = pathManagerLib.typeDetection.normalizePath ".config/🎨/";
      expected = ".config/🎨";
    };

    "special-chars: path segments with unicode" = {
      expr = pathManagerLib.validation.pathSegments ".config/测试/文件.txt";
      expected = [
        ".config"
        "测试"
        "文件.txt"
      ];
    };

  };
}
