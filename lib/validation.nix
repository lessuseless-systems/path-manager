# Validation library for path-manager
#
# Provides shared conflict detection logic used by both HM and NixOS modules.
# Implements full recursive tree analysis for parent-child path conflicts.

{ lib }:

with lib;

let
  typeDetection = import ./type-detection.nix { inherit lib; };

  # Split path into segments
  # Example: ".config/app/file.txt" → [".config" "app" "file.txt"]
  pathSegments = path: filter (s: s != "" && s != "/") (splitString "/" path);

  # Get path depth (number of segments)
  # Example: ".config/app/file.txt" → 3
  pathDepth = path: length (pathSegments path);

  # Check if parentPath is a parent of childPath
  # Example: isParentOf ".config" ".config/app/file.txt" → true
  isParentOf =
    parentPath: childPath:
    let
      parent = typeDetection.normalizePath parentPath;
      child = typeDetection.normalizePath childPath;
      parentSegs = pathSegments parent;
      childSegs = pathSegments child;
      parentLen = length parentSegs;
      childLen = length childSegs;
      # Check if parentSegs is a prefix of childSegs
      isPrefix = parentLen < childLen && (take parentLen childSegs) == parentSegs;
    in
    parent != child && isPrefix;

  # Check if childPath is a child of parentPath
  # (Just a convenience wrapper)
  isChildOf = childPath: parentPath: isParentOf parentPath childPath;

  # Get all ancestor paths of a given path
  # Example: getAllAncestors ".config/app/file.txt" →
  #          [".config" ".config/app"]
  getAllAncestors =
    path:
    let
      segs = pathSegments (typeDetection.normalizePath path);
      # Generate all prefixes: [1] [1 2] [1 2 3] etc.
      prefixes = genList (n: take (n + 1) segs) ((length segs) - 1);
    in
    map (segments: concatStringsSep "/" segments) prefixes;

  # Find all descendants of a path from a set of paths
  # Example: getAllDescendants [".config" ".config/app" ".local"] ".config" →
  #          [".config/app"]
  getAllDescendants =
    paths: parentPath:
    filter (p: isParentOf (typeDetection.normalizePath parentPath) p) paths;

in
{
  # ============================================================================
  # PATH RELATIONSHIP UTILITIES (exported)
  # ============================================================================

  inherit pathSegments pathDepth isParentOf isChildOf getAllAncestors getAllDescendants;

  # ============================================================================
  # EXACT CONFLICT DETECTION
  # ============================================================================

  # Detect exact path matches between pathManager and other sources
  #
  # Arguments:
  #   - pathManagerDecls: attrset of pathManager declarations
  #                       { ".config/app" = { state, type?, source?, text? }; }
  #   - homeFilePaths: list of paths in home.file
  #   - persistenceFiles: list of paths in home.persistence.<root>.files
  #   - persistenceDirs: list of paths in home.persistence.<root>.directories
  #   - warnOnRedundant: bool - whether to warn on harmless redundancy
  #
  # Returns: list of assertion attrsets { assertion, message }
  detectExactConflicts =
    {
      pathManagerDecls,
      homeFilePaths,
      persistenceFiles,
      persistenceDirs,
      warnOnRedundant ? true,
    }:
    flatten (
      mapAttrsToList (
        path: decl:
        let
          normalPath = typeDetection.normalizePath path;
          declType = typeDetection.inferPathType {
            inherit path;
            type = decl.type or null;
            source = decl.source or null;
            text = decl.text or null;
            state = decl.state;
          };

          inHomeFile = elem normalPath homeFilePaths;
          inPersistFiles = elem normalPath persistenceFiles;
          inPersistDirs = elem normalPath persistenceDirs;

          # State expectations
          isImmutable = decl.state == "immutable";
          isEphemeral = decl.state == "ephemeral";
          isMutable = decl.state == "mutable";
          isExtensible = decl.state == "extensible";
          isPersisted = isMutable || isExtensible;

        in
        [
          # Ephemeral conflicts with home.file
          (optionalAttrs (isEphemeral && inHomeFile) {
            assertion = false;
            message = ''
              Path '${normalPath}' has conflicting declarations:

              - Declared in pathManager as: ephemeral (temporary, wiped on reboot)
              - Also declared in: home.file (managed by home-manager)

              These are incompatible. Ephemeral paths should not be managed by home.file.

              Resolution: Remove the home.file declaration.
                home.file."${normalPath}" = ...; # ← Remove this
            '';
          })

          # Ephemeral conflicts with persistence
          (optionalAttrs (isEphemeral && (inPersistFiles || inPersistDirs)) {
            assertion = false;
            message = ''
              Path '${normalPath}' has conflicting declarations:

              - Declared in pathManager as: ephemeral (temporary, wiped on reboot)
              - Also declared in: home.persistence (persisted across reboots)

              These are incompatible. Ephemeral paths should not be persisted.

              Resolution: Remove the persistence declaration.
                home.persistence."...".${if inPersistFiles then "files" else "directories"} = [ "${normalPath}" ]; # ← Remove "${normalPath}"
            '';
          })

          # Immutable conflicts with home.file (non-override case - should be rare after mkForce)
          (optionalAttrs (isImmutable && inHomeFile) {
            assertion = true; # Warning only - mkForce should handle this
            message = ''
              Note: Path '${normalPath}' is declared in both:
              - pathManager (immutable)
              - home.file

              pathManager will override home.file using mkForce. This is expected behavior.
              You may remove the home.file declaration for clarity.
            '';
          })

          # Type mismatch: pathManager file vs persistence directory
          (optionalAttrs (declType == "file" && inPersistDirs) {
            assertion = false;
            message = ''
              Path '${normalPath}' has type mismatch:

              - Declared in pathManager as: file (${decl.state})
              - Declared in home.persistence.directories as: directory

              Resolution: Use consistent types or remove persistence declaration.
            '';
          })

          # Type mismatch: pathManager directory vs persistence files
          (optionalAttrs (declType == "directory" && inPersistFiles) {
            assertion = false;
            message = ''
              Path '${normalPath}' has type mismatch:

              - Declared in pathManager as: directory (${decl.state})
              - Declared in home.persistence.files as: file

              Resolution: Use consistent types or remove persistence declaration.
            '';
          })

          # Redundant but harmless: mutable/extensible file in both pathManager and persistence.files
          (optionalAttrs (warnOnRedundant && declType == "file" && isPersisted && inPersistFiles) {
            assertion = true; # Warning only
            message = ''
              Note: Path '${normalPath}' is declared in both:
              - pathManager (${decl.state})
              - home.persistence.files

              This is redundant. pathManager will handle persistence.
              You may remove the persistence declaration for clarity.
            '';
          })

          # Redundant but harmless: mutable/extensible dir in both pathManager and persistence.directories
          (optionalAttrs (warnOnRedundant && declType == "directory" && isPersisted && inPersistDirs) {
            assertion = true; # Warning only
            message = ''
              Note: Path '${normalPath}' is declared in both:
              - pathManager (${decl.state})
              - home.persistence.directories

              This is redundant. pathManager will handle persistence.
              You may remove the persistence declaration for clarity.
            '';
          })

          # Persisted path conflicts with home.file (non-immutable)
          (optionalAttrs (isPersisted && inHomeFile) {
            assertion = false;
            message = ''
              Path '${normalPath}' has conflicting declarations:

              - Declared in pathManager as: ${decl.state} (persisted, user-managed)
              - Also declared in: home.file (config-managed)

              These are incompatible state expectations.

              Resolution options:
              1. Keep pathManager (${decl.state}) - remove home.file declaration
              2. Make it immutable instead:
                 home.pathManager."${normalPath}" = mkImmutablePath { ... };
            '';
          })
        ]
      ) pathManagerDecls
    );

  # ============================================================================
  # HIERARCHICAL CONFLICT DETECTION (Full Recursive Tree Analysis)
  # ============================================================================

  # Detect parent-child conflicts across all path sources
  #
  # Arguments:
  #   - pathManagerDecls: attrset of pathManager declarations
  #   - homeFilePaths: list of paths in home.file
  #   - persistenceFiles: list of paths in home.persistence.<root>.files
  #   - persistenceDirs: list of paths in home.persistence.<root>.directories
  #
  # Returns: list of assertion attrsets { assertion, message }
  detectHierarchicalConflicts =
    {
      pathManagerDecls,
      homeFilePaths,
      persistenceFiles,
      persistenceDirs,
    }:
    let
      pathManagerPaths = attrNames pathManagerDecls;
      allPaths = unique (pathManagerPaths ++ homeFilePaths ++ persistenceFiles ++ persistenceDirs);

      # Helper: get source of a path
      getPathSource =
        path:
        let
          inPathManager = pathManagerDecls ? ${path};
          inHomeFile = elem path homeFilePaths;
          inPersistFiles = elem path persistenceFiles;
          inPersistDirs = elem path persistenceDirs;
        in
        {
          inherit path;
          sources =
            (optional inPathManager "pathManager")
            ++ (optional inHomeFile "home.file")
            ++ (optional inPersistFiles "persistence.files")
            ++ (optional inPersistDirs "persistence.directories");
          decl = if inPathManager then pathManagerDecls.${path} else null;
        };

      pathSources = map getPathSource allPaths;

      # Find all parent-child conflicts
      conflicts = flatten (
        map (
          pathInfo:
          let
            path = pathInfo.path;
            ancestors = getAllAncestors path;
            descendants = getAllDescendants allPaths path;

            # Find ancestors that are declared somewhere
            declaredAncestors = filter (a: any (s: elem a s.sources) pathSources) (
              map getPathSource ancestors
            );

            # Find descendants that are declared somewhere
            declaredDescendants = filter (d: any (s: elem d s.sources) pathSources) (
              map getPathSource descendants
            );

          in
          # Check for conflicts with ancestors
          (map (ancestor: checkParentChildConflict ancestor pathInfo) declaredAncestors)
          # Check for conflicts with descendants
          ++ (map (descendant: checkParentChildConflict pathInfo descendant) declaredDescendants)
        ) pathSources
      );

    in
    filter (c: c != null) conflicts;

  # Check for conflict between parent and child paths
  # Returns: null or { assertion, message }
  checkParentChildConflict =
    parent: child:
    let
      parentPath = parent.path;
      childPath = child.path;
      parentSources = parent.sources;
      childSources = child.sources;

      # Skip if same path or not actually parent-child
      skip = parentPath == childPath || !(isParentOf parentPath childPath);

      # Get declarations
      parentInPM = elem "pathManager" parentSources;
      parentInHF = elem "home.file" parentSources;
      parentInPF = elem "persistence.files" parentSources;
      parentInPD = elem "persistence.directories" parentSources;

      childInPM = elem "pathManager" childSources;
      childInHF = elem "home.file" childSources;
      childInPF = elem "persistence.files" childSources;
      childInPD = elem "persistence.directories" childSources;

      parentDecl = parent.decl;
      childDecl = child.decl;

      # Conflict scenarios
      # 1. home.file DIR (parent) + pathManager (child)
      homeFileParentPMChild = parentInHF && childInPM;

      # 2. persistence.directories (parent) + pathManager immutable/ephemeral (child)
      persistDirParentIncompatibleChild =
        parentInPD && childInPM
        && (childDecl.state == "immutable" || childDecl.state == "ephemeral");

      # 3. pathManager DIR (parent) + home.file (child)
      pmParentHomeFileChild = parentInPM && childInHF;

      # 4. pathManager immutable/ephemeral DIR (parent) + persistence (child)
      pmIncompatibleParentPersistChild =
        parentInPM && (childInPF || childInPD)
        && (parentDecl.state == "immutable" || parentDecl.state == "ephemeral");

      # 5. pathManager mutable/extensible DIR (parent) + persistence (child) - just warn
      pmMutableParentPersistChild =
        parentInPM && (childInPF || childInPD)
        && (parentDecl.state == "mutable" || parentDecl.state == "extensible");

    in
    if skip then
      null
    else if homeFileParentPMChild then
      {
        assertion = false;
        message = ''
          Hierarchical conflict detected:

          Parent: '${parentPath}' declared in home.file (directory)
          Child:  '${childPath}' declared in pathManager (${childDecl.state})

          Issue: Parent directory is managed by home-manager, but child path is managed by pathManager.
          This creates ownership conflicts.

          Resolution: Remove home.file parent declaration and manage via pathManager:
            home.pathManager."${childPath}" = mk${
              if childDecl.state == "immutable" then "ImmutablePath"
              else if childDecl.state == "mutable" then "MutablePath"
              else if childDecl.state == "ephemeral" then "EphemeralPath"
              else "ExtensiblePath"
            } { ... };
        '';
      }
    else if persistDirParentIncompatibleChild then
      {
        assertion = false;
        message = ''
          Hierarchical conflict detected:

          Parent: '${parentPath}' declared in home.persistence.directories (mutable, persisted)
          Child:  '${childPath}' declared in pathManager (${childDecl.state})

          Issue: Parent directory is persisted (mutable), but child is ${childDecl.state}.
          ${
            if childDecl.state == "immutable" then
              "Cannot have immutable child inside mutable parent directory."
            else
              "Cannot have ephemeral child inside persisted parent directory."
          }

          Resolution options:
          1. Remove persistence.directories parent, manage child via pathManager
          2. Remove pathManager child declaration (let parent directory persistence handle it)
        '';
      }
    else if pmParentHomeFileChild then
      {
        assertion = false;
        message = ''
          Hierarchical conflict detected:

          Parent: '${parentPath}' declared in pathManager (${parentDecl.state})
          Child:  '${childPath}' declared in home.file

          Issue: Parent is managed by pathManager, child by home-manager.
          This creates ownership conflicts.

          Resolution: Remove home.file child, let pathManager handle parent:
            # Remove or convert to pathManager:
            home.file."${childPath}" = ...; # ← Remove this
        '';
      }
    else if pmIncompatibleParentPersistChild then
      {
        assertion = false;
        message = ''
          Hierarchical conflict detected:

          Parent: '${parentPath}' declared in pathManager (${parentDecl.state})
          Child:  '${childPath}' declared in home.persistence.${if childInPF then "files" else "directories"}

          Issue: Parent is ${parentDecl.state}, but child is persisted.
          ${
            if parentDecl.state == "immutable" then
              "Cannot persist child inside immutable parent (parent is recreated)."
            else
              "Cannot persist child inside ephemeral parent (parent is wiped)."
          }

          Resolution: Remove persistence child declaration.
        '';
      }
    else if pmMutableParentPersistChild then
      {
        assertion = true; # Warning only
        message = ''
          Note: Redundant declaration detected:

          Parent: '${parentPath}' declared in pathManager (${parentDecl.state})
          Child:  '${childPath}' declared in home.persistence.${if childInPF then "files" else "directories"}

          This is redundant. Parent directory persistence already covers children.
          You may remove the child persistence declaration for clarity.
        '';
      }
    else
      null;
}
