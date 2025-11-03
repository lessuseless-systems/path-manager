# Project TODO List: `path-manager` Home Manager Module

This document outlines the remaining tasks for developing the `path-manager` Home Manager module, following a Test-Driven Development (TDD) approach.

## 1. Implement Core Module Functionality (TDD Cycle)

For each scenario, we will follow the TDD cycle:

- **Red**: Write a failing test.
- **Green**: Implement the minimum code to make the test pass.
- **Refactor**: Improve the code's structure and readability.

### 1.1. Scenario: `immutable` (Read-only)

- \[x\] Write failing test for `immutable` state.
- \[x\] Implement `immutable` state logic in `path-manager.nix`.
- \[x\] Run tests and confirm `immutable` test passes.
- \[ \] Refactor `immutable` implementation (if necessary).

### 1.2. Scenario: `ephemeral` (Temporary)

- \[x\] Write failing test for `ephemeral` state.
- \[x\] Implement `ephemeral` state logic in `path-manager.nix`.
- \[x\] Run tests and confirm `ephemeral` test passes.
- \[ \] Refactor `ephemeral` implementation (if necessary).

### 1.3. Scenario: `mutable` (Persistent)

- \[x\] Write failing test for `mutable` state.
- \[ \] Implement `mutable` state logic in `path-manager.nix`.
- \[ \] Run tests and confirm `mutable` test passes.
- \[ \] Refactor `mutable` implementation (if necessary).

### 1.4. Scenario: `extensible` (Persistent with Initial Content)

- \[ \] Write failing test for `extensible` state.
- \[ \] Implement `extensible` state logic in `path-manager.nix` (Linux `systemd.tmpfiles.rules`).
- \[ \] Run tests and confirm `extensible` test passes on Linux.
- \[ \] Refactor `extensible` implementation (if necessary).

## 2. Cross-Platform Support (`nix-darwin`)

- \[ \] Implement `extensible` state logic for `nix-darwin` using `launchd`.
- \[ \] Write specific tests for `nix-darwin` `extensible` state.
- \[ \] Run tests on `nix-darwin` and confirm `extensible` test passes.

## 3. Comprehensive Testing

- \[ \] Configure `checkmate` to run tests for all compatible systems (`--all-systems`).
- \[ \] Add more edge case tests for all scenarios.

## 4. Documentation and Cleanup

- \[ \] Add comprehensive documentation to `path-manager.nix`.
- \[ \] Ensure all code adheres to Nix best practices and style guides.
- \[ \] Remove temporary files and directories.
- \[ \] Prepare for potential PR to `impermanence` project.
