# Release

Releases are automated. Pushing a `vX.Y.Z` tag triggers the [`release.yml`](.github/workflows/release.yml) workflow which builds the DMG, CLI binary, checksums, creates a GitHub Release, and updates the Homebrew tap.

The `release.sh` script handles the local part: version bump, commit, tag, and push.

## Usage

```bash
# Dry-run (default) — shows what would happen
./release.sh patch          # 1.1.1 → 1.1.2
./release.sh minor          # 1.1.1 → 1.2.0
./release.sh major          # 1.1.1 → 2.0.0
./release.sh 2.0.0          # explicit version

# Actually perform the release
./release.sh --execute patch
```

## What it does

1. Validates you're on `main` with a clean working tree
2. Updates `Cargo.toml` (`workspace.package.version`)
3. Updates `DiktoApp/Resources/Info.plist` (`CFBundleShortVersionString`)
4. Regenerates `Cargo.lock`
5. Commits: `Bump version to X.Y.Z`
6. Tags: `vX.Y.Z`
7. Pushes commit + tag to origin

## Manual release

If you need to do it by hand:

```bash
# Edit version in these two files:
#   Cargo.toml              → [workspace.package] version
#   DiktoApp/Resources/Info.plist → CFBundleShortVersionString

cargo generate-lockfile
git add Cargo.toml DiktoApp/Resources/Info.plist Cargo.lock
git commit -m "Bump version to X.Y.Z"
git tag vX.Y.Z
git push && git push --tags
```
