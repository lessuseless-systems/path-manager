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
      # Home Manager module - universal, works on any platform
      homeManagerModules.default = import ./path-manager.nix;
      homeManagerModules.path-manager = import ./path-manager.nix;

      # NixOS module - full conflict detection for NixOS + impermanence
      nixosModules.default = import ./nixos-module.nix;
      nixosModules.path-manager = import ./nixos-module.nix;

      # Legacy exports for compatibility
      flakeModule = import ./path-manager.nix;
      flakeModules.checkmate = import ./checkmate.nix;

      # Library functions
      lib = import ./lib { inherit lib; };
    };
}
