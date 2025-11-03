# Test Suite Aggregator for path-manager
# Imports and combines all test category modules into a unified test suite
#
# This provides a modular test structure where tests are organized by category
# for easier navigation and maintenance, while still being runnable as a single suite.

{ inputs, ... }:

let
  # Import all test category modules
  typeDetection = import ./type-detection.nix { inherit inputs; };
  directories = import ./directories.nix { inherit inputs; };
  pathRelationships = import ./path-relationships.nix { inherit inputs; };
  exactConflicts = import ./exact-conflicts.nix { inherit inputs; };
  hierarchicalConflicts = import ./hierarchical-conflicts.nix { inherit inputs; };
  integration = import ./integration.nix { inherit inputs; };
  threeWayConflicts = import ./three-way-conflicts.nix { inherit inputs; };
  persistenceRoots = import ./persistence-roots.nix { inherit inputs; };
  unicodeSpecialChars = import ./unicode-special-chars.nix { inherit inputs; };
  pathsNormalization = import ./paths-normalization.nix { inherit inputs; };
  performance = import ./performance.nix { inherit inputs; };
  complexHierarchies = import ./complex-hierarchies.nix { inherit inputs; };
  edgeCases = import ./edge-cases.nix { inherit inputs; };
  stress = import ./stress.nix { inherit inputs; };
  filesystemValidation = import ./filesystem-validation.nix { inherit inputs; };

  # Merge all test suites into one
  pkgs = import inputs.target.inputs.nixpkgs { system = "x86_64-linux"; };
  mergedTests = pkgs.lib.mkMerge [
    typeDetection.perSystem.nix-unit.tests
    directories.perSystem.nix-unit.tests
    pathRelationships.perSystem.nix-unit.tests
    exactConflicts.perSystem.nix-unit.tests
    hierarchicalConflicts.perSystem.nix-unit.tests
    integration.perSystem.nix-unit.tests
    threeWayConflicts.perSystem.nix-unit.tests
    persistenceRoots.perSystem.nix-unit.tests
    unicodeSpecialChars.perSystem.nix-unit.tests
    pathsNormalization.perSystem.nix-unit.tests
    performance.perSystem.nix-unit.tests
    complexHierarchies.perSystem.nix-unit.tests
    edgeCases.perSystem.nix-unit.tests
    stress.perSystem.nix-unit.tests
    filesystemValidation.perSystem.nix-unit.tests
  ];

in
{
  # Combined test suite (all 125 tests)
  perSystem.nix-unit.tests = mergedTests;

  # Individual category exports for targeted testing (optional)
  categories = {
    inherit
      typeDetection
      directories
      pathRelationships
      exactConflicts
      hierarchicalConflicts
      integration
      threeWayConflicts
      persistenceRoots
      unicodeSpecialChars
      pathsNormalization
      performance
      complexHierarchies
      edgeCases
      stress
      filesystemValidation
      ;
  };
}
