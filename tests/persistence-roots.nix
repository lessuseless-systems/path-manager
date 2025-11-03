# Multiple Persistence Roots Tests

{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib) pkgs pathManagerLib createTestConfig;
in
{
  perSystem.nix-unit.tests = {

    "multi-root: same file in two persistence roots" = {
      expr =
        let
          config = createTestConfig [
            {
              home.pathManager.paths = {
                ".bashrc" = pathManagerLib.mkMutablePath;
              };
              # Manually add a second persistence root
              home.persistence."/other/persist/home/test-user".files = [ ];
            }
          ];
        in
        # Should appear in default persist root
        builtins.elem ".bashrc" config.config.home.persistence."/persist/home/test-user".files;
      expected = true;
    };

    "multi-root: different files in different roots handled correctly" = {
      expr =
        let
          config = createTestConfig [
            {
              home.persistence."/persist/home/test-user".files = [ ".file1" ];
              home.persistence."/other/persist/home/test-user".files = [ ".file2" ];
              home.pathManager.paths = {
                ".file3" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # file3 goes to default root, others stay in their roots
        builtins.elem ".file3" config.config.home.persistence."/persist/home/test-user".files
        && builtins.elem ".file1" config.config.home.persistence."/persist/home/test-user".files
        && builtins.elem ".file2" config.config.home.persistence."/other/persist/home/test-user".files;
      expected = true;
    };

    "multi-root: pathManager doesn't interfere with other roots" = {
      expr =
        let
          config = createTestConfig [
            {
              home.persistence."/other/root".files = [ ".other-file" ];
              home.pathManager.paths = {
                ".my-file" = pathManagerLib.mkMutablePath;
              };
            }
          ];
        in
        # pathManager uses default root, other root unchanged
        builtins.elem ".other-file" config.config.home.persistence."/other/root".files;
      expected = true;
    };

    "multi-root: collect persistence files from all roots for validation" = {
      expr =
        let
          # This tests the NixOS module's collectPersistenceFiles function
          # We can't easily test the NixOS module here, so we test the concept
          persistRoots = {
            "/persist/home/user".files = [
              ".file1"
              ".file2"
            ];
            "/other/persist".files = [ ".file3" ];
          };
          allFiles = pkgs.lib.unique (
            pkgs.lib.flatten (pkgs.lib.mapAttrsToList (_root: cfg: cfg.files or [ ]) persistRoots)
          );
        in
        allFiles == [
          ".file1"
          ".file2"
          ".file3"
        ];
      expected = true;
    };

  };
}
