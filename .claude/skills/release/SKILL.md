---
name: release
description: Cut a new release — bumps version, creates PR, tags, and triggers CI
argument-hint: <patch|minor|major|X.Y.Z>
disable-model-invocation: true
---

# Release Workflow

You are cutting a new release for Dikto. The user provided `$ARGUMENTS` which should be one of: `patch`, `minor`, `major`, or an explicit semver like `X.Y.Z`.

If `$ARGUMENTS` is empty or missing, ask the user which bump type they want.

## Constants

- **Cargo.toml**: `Cargo.toml` (workspace root)
- **Info.plist**: `DiktoApp/Resources/Info.plist`
- **GitHub repo**: `diktoapp/dikto`

## Steps

### 1. Validate preconditions

- Confirm you are on `main` branch (`git rev-parse --abbrev-ref HEAD`)
- Pull latest from origin (`git pull --ff-only origin main`)
- Confirm working tree is clean (`git status --porcelain` should be empty)
- If any check fails, stop and tell the user what's wrong

### 2. Compute the new version

- Read the current version from `Cargo.toml` under `[workspace.package]` → `version = "X.Y.Z"`
- Parse it into MAJOR, MINOR, PATCH integers
- Based on `$ARGUMENTS`:
  - `patch` → `MAJOR.MINOR.(PATCH+1)`
  - `minor` → `MAJOR.(MINOR+1).0`
  - `major` → `(MAJOR+1).0.0`
  - Explicit `X.Y.Z` → use as-is (validate it matches `^\d+\.\d+\.\d+$`)
- Confirm the new version differs from the current version
- Confirm tag `vX.Y.Z` does not already exist (`git tag -l "vX.Y.Z"`)
- **Show the user the planned bump** (e.g., `1.2.0 → 1.2.1`) and **ask for confirmation** before proceeding

### 3. Create release branch

```
git checkout -b release/vX.Y.Z
```

### 4. Bump version in all files

Update these files with the new version:

1. **`Cargo.toml`** — change `version = "..."` under `[workspace.package]`
2. **`DiktoApp/Resources/Info.plist`** — change the `<string>` value after `CFBundleShortVersionString`
3. **`Cargo.lock`** — regenerate by running `cargo generate-lockfile`

### 5. Commit

```
git add Cargo.toml DiktoApp/Resources/Info.plist Cargo.lock
git commit -m "Bump version to X.Y.Z"
```

### 6. Create and push the tag

Push the tag first — this triggers the release CI workflow on GitHub Actions immediately. Tags are not subject to branch protection rules.

```
git tag vX.Y.Z
git push origin vX.Y.Z
```

### 7. Push the release branch and create PR

```
git push -u origin release/vX.Y.Z
```

Then create a PR using `gh`:

```
gh pr create --base main --head release/vX.Y.Z \
  --title "Bump version to X.Y.Z" \
  --body "Release vX.Y.Z — version bump for Cargo.toml, Info.plist, and Cargo.lock."
```

### 8. Report

Print a summary with:

- The new version number
- Link to the GitHub Actions run: `https://github.com/diktoapp/dikto/actions`
- Link to the PR (from `gh pr create` output)
- Remind the user to merge the PR once CI passes
