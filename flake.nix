{
  description = "A Home Manager module for managing paths in an impermanent setup.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
    in
    {
      # Home Manager modules - universal, works on any platform
      homeManagerModules = import ./modules/home-manager;

      # NixOS module - full conflict detection for NixOS + impermanence
      nixosModules.default = import ./modules/nixos;
      nixosModules.path-manager = import ./modules/nixos;

      # flake-parts module - TODO: implement perSystem integration
      flakePartsModules.default = import ./modules/flake-parts;
      flakePartsModules.path-manager = import ./modules/flake-parts;

      # Legacy exports for compatibility
      flakeModule = import ./modules/home-manager/path-manager;
      flakeModules.checkmate = import ./tests/checkmate.nix;
      flakeModules.checkmate-comprehensive = import ./tests/checkmate-comprehensive.nix;

      # Library functions
      lib = import ./lib { inherit lib; };
    };
}
