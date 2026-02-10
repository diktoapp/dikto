#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
CARGO_TOML="Cargo.toml"
INFO_PLIST="DiktoApp/Resources/Info.plist"
GITHUB_REPO="diktoapp/dikto"

# ── Helpers ─────────────────────────────────────────────────────
die()  { echo "error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

usage() {
  cat <<EOF
Usage: $0 [--execute] <version|patch|minor|major>

Bump the project version, commit, tag, and push.

Arguments:
  <version>   Explicit semver (e.g. 1.2.0)
  patch       Bump patch: 1.1.1 → 1.1.2
  minor       Bump minor: 1.1.1 → 1.2.0
  major       Bump major: 1.1.1 → 2.0.0

Options:
  --execute   Actually perform the release (dry-run by default)
  -h, --help  Show this help
EOF
  exit 0
}

# ── Parse arguments ─────────────────────────────────────────────
EXECUTE=false
VERSION_ARG=""

for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=true ;;
    -h|--help) usage ;;
    *)
      [ -z "$VERSION_ARG" ] || die "unexpected argument: $arg"
      VERSION_ARG="$arg"
      ;;
  esac
done

[ -n "$VERSION_ARG" ] || die "version argument required (run with --help for usage)"

# ── Read current version from Cargo.toml ────────────────────────
CURRENT=$(sed -n '/\[workspace\.package\]/,/^\[/{ s/^version = "\(.*\)"/\1/p; }' "$CARGO_TOML")
[ -n "$CURRENT" ] || die "could not read current version from $CARGO_TOML"

IFS='.' read -r CUR_MAJOR CUR_MINOR CUR_PATCH <<< "$CURRENT"

# ── Resolve target version ──────────────────────────────────────
case "$VERSION_ARG" in
  major) NEW_VERSION="$((CUR_MAJOR + 1)).0.0" ;;
  minor) NEW_VERSION="${CUR_MAJOR}.$((CUR_MINOR + 1)).0" ;;
  patch) NEW_VERSION="${CUR_MAJOR}.${CUR_MINOR}.$((CUR_PATCH + 1))" ;;
  *)     NEW_VERSION="$VERSION_ARG" ;;
esac

# Validate semver format
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid semver: $NEW_VERSION"

# Refuse no-op
[ "$NEW_VERSION" != "$CURRENT" ] || die "version $NEW_VERSION is already the current version"

# ── Validate preconditions ──────────────────────────────────────
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || die "must be on main branch (currently on $BRANCH)"

if [ -n "$(git status --porcelain)" ]; then
  die "working tree is dirty — commit or stash changes first"
fi

if git rev-parse "v${NEW_VERSION}" >/dev/null 2>&1; then
  die "tag v${NEW_VERSION} already exists"
fi

# ── Show plan ───────────────────────────────────────────────────
echo ""
echo "  Version bump: $CURRENT → $NEW_VERSION"
echo ""
echo "  Files to update:"
echo "    $CARGO_TOML          (workspace.package.version)"
echo "    $INFO_PLIST           (CFBundleShortVersionString)"
echo "    Cargo.lock             (regenerated)"
echo ""
echo "  Git operations:"
echo "    commit  \"Bump version to $NEW_VERSION\""
echo "    tag     v$NEW_VERSION"
echo "    push    origin main + tags"
echo ""

if [ "$EXECUTE" = false ]; then
  echo "Dry run — no changes made. Re-run with --execute to perform the release."
  exit 0
fi

# ── Confirm ─────────────────────────────────────────────────────
read -rp "Proceed with release $NEW_VERSION? [y/N] " CONFIRM
case "$CONFIRM" in
  [yY]) ;;
  *)    echo "Aborted."; exit 1 ;;
esac

# ── Update Cargo.toml ───────────────────────────────────────────
info "Updating $CARGO_TOML"
sed -i '' "/\[workspace\.package\]/,/^\[/ s/^version = \".*\"/version = \"$NEW_VERSION\"/" "$CARGO_TOML"

# ── Update Info.plist ───────────────────────────────────────────
info "Updating $INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"

# ── Regenerate Cargo.lock ───────────────────────────────────────
info "Regenerating Cargo.lock"
cargo generate-lockfile

# ── Commit, tag, push ──────────────────────────────────────────
info "Committing changes"
git add "$CARGO_TOML" "$INFO_PLIST" Cargo.lock
git commit -m "Bump version to $NEW_VERSION"

info "Tagging v$NEW_VERSION"
git tag "v$NEW_VERSION"

info "Pushing to origin"
git push && git push --tags

# ── Done ────────────────────────────────────────────────────────
echo ""
echo "Release v$NEW_VERSION pushed! Monitor the build:"
echo "  https://github.com/$GITHUB_REPO/actions"
