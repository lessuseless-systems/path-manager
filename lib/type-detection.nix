# Type detection for path-manager
#
# Determines whether a path declaration represents a file or directory
# based on various heuristics and explicit overrides.

{ lib }:

with lib;

{
  # Infer path type from declaration
  # Returns: "file" or "directory"
  #
  # Arguments:
  #   - path: The path string (e.g., ".config/app" or ".config/app/")
  #   - type: Optional explicit type override ("file" or "directory" or null)
  #   - source: Optional source path
  #   - text: Optional text content
  #   - state: Path state ("immutable", "ephemeral", "mutable", "extensible")
  #
  # Detection rules (in order of precedence):
  #   1. Explicit type override → use it
  #   2. Trailing slash → directory
  #   3. source is directory → directory (requires path existence check)
  #   4. No source/text + (mutable|ephemeral) → directory
  #   5. Has source or text → file
  #   6. Default → file
  inferPathType =
    {
      path,
      type ? null,
      source ? null,
      text ? null,
      state,
    }:
    if type != null then
      # Rule 1: Explicit override
      type
    else if hasSuffix "/" path then
      # Rule 2: Trailing slash convention
      "directory"
    else if source != null && pathIsDirectory source then
      # Rule 3: Source is a directory
      "directory"
    else if source == null && text == null && (state == "mutable" || state == "ephemeral") then
      # Rule 4: No content + mutable/ephemeral → likely directory
      "directory"
    else if source != null || text != null then
      # Rule 5: Has content → file
      "file"
    else
      # Rule 6: Default fallback
      "file";

  # Check if a path is a directory
  # Returns: bool
  #
  # Note: This requires the path to exist at evaluation time.
  # For non-existent paths, this will return false.
  pathIsDirectory = path: builtins.pathExists path && (builtins.readFileType (toString path)) == "directory";

  # Normalize path by removing trailing slash
  # This is useful for comparing paths
  normalizePath = path: removeSuffix "/" path;

  # Check if a pathManager declaration represents a directory
  # This is a convenience wrapper around inferPathType
  isDirectoryDeclaration = pathDecl: (inferPathType pathDecl) == "directory";
}
