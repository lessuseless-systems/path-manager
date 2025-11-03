{
  description = "A Home Manager module for managing paths in an impermanent setup.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs =
    { ... }:
    {
      flakeModule = import ./path-manager.nix;
      flakeModules.checkmate = import ./checkmate.nix;
    };
}
