# path-manager library functions
# Provides convenient helpers for declaring path states

{ lib }:

{
  # Create an immutable path managed by home-manager
  # The file will be recreated from source/text on each activation
  #
  # Usage:
  #   mkImmutablePath { text = "content"; }
  #   mkImmutablePath { source = ./path/to/file; }
  mkImmutablePath =
    {
      source ? null,
      text ? null,
    }:
    {
      state = "immutable";
      inherit source text;
    };

  # Create a mutable path that persists across reboots
  # The file is stored in the persistence layer with no initial content
  #
  # Usage:
  #   mkMutablePath
  mkMutablePath = {
    state = "mutable";
  };

  # Create an ephemeral path that lives in tmpfs
  # The file will be wiped on each reboot
  #
  # Usage:
  #   mkEphemeralPath
  mkEphemeralPath = {
    state = "ephemeral";
  };

  # Create an extensible path with initial content
  # The file persists across reboots and is initialized with source/text if it doesn't exist
  # After creation, the file can be modified freely
  #
  # Usage:
  #   mkExtensiblePath { text = "initial content"; }
  #   mkExtensiblePath { source = ./path/to/file; }
  mkExtensiblePath =
    {
      source ? null,
      text ? null,
    }:
    {
      state = "extensible";
      inherit source text;
    };
}
