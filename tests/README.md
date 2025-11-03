# Test Suite Organization

This directory contains the path-manager test suite, organized into modular category files for easier navigation and maintenance.

## Structure

### Modular Test Files (Recommended)

The test suite is split into 15 focused category files:

| File | Tests | Description |
|------|-------|-------------|
| `type-detection.nix` | 8 | File vs directory type inference |
| `directories.nix` | 8 | Directory-specific behaviors and persistence |
| `path-relationships.nix` | 6 | Path manipulation and hierarchy utilities |
| `exact-conflicts.nix` | 33 | Same-path conflict detection |
| `hierarchical-conflicts.nix` | 41 | Parent-child relationship conflicts |
| `integration.nix` | 3 | Real-world integration scenarios |
| `three-way-conflicts.nix` | 10 | pathManager + home.file + persistence conflicts |
| `persistence-roots.nix` | 4 | Multiple persistence root handling |
| `unicode-special-chars.nix` | 6 | Unicode and special character path support |
| `paths-normalization.nix` | 4 | Path normalization (absolute/relative, trailing slashes) |
| `performance.nix` | 3 | Performance with 100-500 paths |
| `complex-hierarchies.nix` | 11 | Deep nesting and complex hierarchies |
| `edge-cases.nix` | 4 | Empty paths and null value handling |
| `stress.nix` | 10 | Stress testing with 1000+ paths |
| `filesystem-validation.nix` | 12 | tmpfiles.d syntax and filesystem correctness |

**Total: 163 tests**

### Supporting Files

- `lib.nix` - Shared test infrastructure (createTestConfig, pathManagerLib)
- `default.nix` - Aggregator that combines all category modules

### Legacy Files

- `checkmate.nix` - Original 10 basic tests (deprecated, kept for compatibility)
- `checkmate-comprehensive.nix` - Original monolithic 163-test file (deprecated)

## Running Tests

### All Tests

```bash
# Using nix-unit
nix run github:nix-community/nix-unit -- --flake .#flakeModules.tests

# Using flake check (if configured)
nix flake check
```

### Individual Categories

Each category file can be imported and tested independently:

```bash
# Test only type detection
nix-instantiate --eval --strict -E '
  let tests = import ./tests/type-detection.nix { inputs = ...; };
  in tests.perSystem.nix-unit.tests
'
```

### In Your Flake

```nix
{
  inputs.path-manager.url = "github:yourorg/path-manager-module-checkmate";

  outputs = { path-manager, ... }: {
    # Use modular tests (recommended)
    checks.x86_64-linux = path-manager.flakeModules.tests;

    # Or use legacy comprehensive file
    checks.x86_64-linux = path-manager.flakeModules.checkmate-comprehensive;
  };
}
```

## Test Organization Benefits

✅ **Easier Navigation** - Find tests by category instead of scrolling through 2000+ lines
✅ **Faster Development** - Run only relevant test categories during development
✅ **Better Maintainability** - Clear separation of concerns
✅ **Follows Conventions** - Matches nixpkgs test organization patterns
✅ **Backward Compatible** - Legacy monolithic files still available

## Adding New Tests

1. Choose the appropriate category file (or create a new one)
2. Add your test following the existing pattern:

```nix
"category: test description" = {
  expr = let
    # Test setup
  in
    # Expression to evaluate;
  expected = # Expected result;
};
```

3. If creating a new category file:
   - Use `tests/lib.nix` for shared infrastructure
   - Export `{ perSystem.nix-unit.tests = { ... }; }`
   - Add to `tests/default.nix` imports and merge list

4. Update this README with the new category

## File Sizes

- **Modular approach**: 15 files × ~150-300 lines = easier to navigate
- **Monolithic approach**: 1 file × 2196 lines = harder to maintain

## Migration Notes

The refactoring from `checkmate-comprehensive.nix` to modular files was a pure structural change with no behavioral modifications. All 163 tests were preserved exactly as written.

**Changes:**
- Split single 2196-line file into 15 focused category files
- Extracted common infrastructure into `lib.nix`
- Created `default.nix` aggregator
- Updated flake.nix to export `flakeModules.tests`

**Compatibility:**
- Legacy exports (`checkmate.nix`, `checkmate-comprehensive.nix`) remain available
- All tests have identical behavior
- Test count unchanged (163 tests)