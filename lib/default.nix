# path-manager library functions
# Provides convenient helpers for declaring path states

{ lib }:

{
  # ==========================================================================
  # PATH STATE HELPER FUNCTIONS
  # ==========================================================================

  # Create an immutable path managed by home-manager
  # The file will be recreated from source/text on each activation
  #
  # Usage:
  #   mkImmutablePath { text = "content"; }
  #   mkImmutablePath { source = ./path/to/file; }
  #   mkImmutablePath { source = ./dir; type = "directory"; }
  mkImmutablePath =
    {
      source ? null,
      text ? null,
      type ? null,
    }:
    {
      state = "immutable";
      inherit source text type;
    };

  # Create a mutable path that persists across reboots
  # The file is stored in the persistence layer with no initial content
  #
  # Usage:
  #   mkMutablePath                    # Type auto-detected
  #   mkMutablePath // { type = "directory"; }  # Override type
  mkMutablePath = {
    state = "mutable";
    type = null;
  };

  # Create an ephemeral path that lives in tmpfs
  # The file will be wiped on each reboot
  #
  # Usage:
  #   mkEphemeralPath                  # Type auto-detected
  #   mkEphemeralPath // { type = "directory"; }  # Override type
  mkEphemeralPath = {
    state = "ephemeral";
    type = null;
  };

  # Create an extensible path with initial content
  # The file persists across reboots and is initialized with source/text if it doesn't exist
  # After creation, the file can be modified freely
  #
  # Usage:
  #   mkExtensiblePath { text = "initial content"; }
  #   mkExtensiblePath { source = ./path/to/file; }
  #   mkExtensiblePath { source = ./dir; type = "directory"; }
  mkExtensiblePath =
    {
      source ? null,
      text ? null,
      type ? null,
    }:
    {
      state = "extensible";
      inherit source text type;
    };

  # ==========================================================================
  # TYPE DETECTION AND VALIDATION
  # ==========================================================================

  # Type detection utilities
  # Provides functions for inferring whether a path is a file or directory
  typeDetection = import ./type-detection.nix { inherit lib; };

  # Validation utilities
  # Provides shared conflict detection logic for both HM and NixOS modules
  validation = import ./validation.nix { inherit lib; };
}
