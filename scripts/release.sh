#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat <<'USAGE'
Usage: bash scripts/release.sh [--dry-run] [--prerelease] [--notes-file FILE]

Release the version in resources/Info.plist from a clean, pushed main branch.
Runs lint/tests, builds the DMG, pushes v<VERSION>, and creates a draft GitHub
release with the DMG and SHA-256 attached. Publish the draft on GitHub when ready.
Requires GitHub CLI authentication, macOS build tools and the usual signing setup.

--dry-run       Check local/remote Git state and print the plan; no build or writes.
--prerelease    Mark the draft as a prerelease.
--notes-file    Use the supplied release notes instead of generated change notes.
USAGE
}
fail() { printf 'Release stopped: %s\n' "$*" >&2; exit 1; }
dry_run=false
prerelease=false
notes_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --prerelease) prerelease=true; shift ;;
        --notes-file)
            [[ $# -ge 2 ]] || fail '--notes-file needs a file path.'
            notes_file="$2"
            [[ -f "$notes_file" ]] || fail 'Release notes file does not exist.'
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "Unknown argument: $1" ;;
    esac
done

command -v gh >/dev/null || fail 'Install GitHub CLI and run gh auth login first.'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' resources/Info.plist)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'App version must have the form X.Y.Z.'
tag="v$version"
commit=$(git rev-parse HEAD)
[[ $(git branch --show-current) == main ]] || fail 'Switch to main before releasing.'
[[ -z $(git status --porcelain --untracked-files=all) ]] || fail 'Commit or set aside all source changes before releasing.'
remote_main=$(git ls-remote --exit-code origin refs/heads/main) || fail 'Cannot read origin/main.'
[[ "${remote_main%%[[:space:]]*}" == "$commit" ]] || fail 'Local main must match origin/main. Push or synchronize it first.'
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || fail 'Cannot access the GitHub repository; check gh authentication.'
[[ -n "$repo" ]] || fail 'GitHub did not return a repository.'
# Refuse a gh repository override that points somewhere other than origin.
origin_url=$(git remote get-url origin)
case "$origin_url" in
    "https://github.com/$repo"|"https://github.com/$repo.git"|"git@github.com:$repo"|"git@github.com:$repo.git") ;;
    *) fail 'The GitHub CLI repository must match the github.com origin remote.' ;;
esac

if git show-ref --verify --quiet "refs/tags/$tag"; then
    [[ $(git rev-parse "$tag^{commit}") == "$commit" ]] || fail "$tag already identifies another local commit. Bump the app version."
fi
remote_tags=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}") || fail 'Cannot read remote tags.'
remote_tag_commit=$(printf '%s\n' "$remote_tags" | awk 'NF { direct=$1 } /\^\{\}$/ { peeled=$1 } END { print peeled ? peeled : direct }')
if [[ -n "$remote_tag_commit" && "$remote_tag_commit" != "$commit" ]]; then
    fail "$tag already identifies another remote commit. Bump the app version."
fi
asset="dist/Disk-Assessment-$version-$(uname -m).dmg"
printf 'Repository: %s\nVersion: %s\nCommit: %s\nAssets: %s and SHA-256\nDestination: draft release (prerelease=%s)\n' "$repo" "$tag" "$commit" "$asset" "$prerelease"
if [[ "$dry_run" == true ]]; then
    printf 'Dry run complete. No checks/build, tags or release writes performed.\n'
    exit 0
fi

make lint test
make dmg
[[ -s "$asset" && -s "$asset.sha256" ]] || fail 'Packaging did not produce both assets.'
(cd dist && shasum -a 256 -c "$(basename "$asset").sha256")
[[ $(git rev-parse HEAD) == "$commit" && -z $(git status --porcelain --untracked-files=all) ]] || fail 'Source changed during the build; release aborted.'
# Do not publish a tag if main advanced while building.
remote_main=$(git ls-remote --exit-code origin refs/heads/main) || fail 'Cannot recheck origin/main.'
[[ "${remote_main%%[[:space:]]*}" == "$commit" ]] || fail 'origin/main changed during the build; synchronize and retry.'
if [[ -z "$remote_tag_commit" ]]; then
    if ! git show-ref --verify --quiet "refs/tags/$tag"; then
        git tag -a "$tag" "$commit" -m "Disk Assessment $version"
    fi
    git push origin "refs/tags/$tag:refs/tags/$tag"
fi

mkdir -p .build
release_notes=$(mktemp "$PWD/.build/release-notes.XXXXXX")
trap 'rm -f "$release_notes"' EXIT
if [[ -n "$notes_file" ]]; then
    cat "$notes_file" > "$release_notes"
fi
cat >> "$release_notes" <<'NOTES'

## Installation

macOS 13 or newer; use the image matching your Mac’s architecture. Open the DMG, drag Disk Assessment into Applications,
then launch it from Applications. Choose a folder or your Mac to assess storage. Scans are read-only.

This build uses local signing and is not notarized. Gatekeeper acceptance on other
Macs is not established. The SHA-256 file verifies the downloaded DMG's integrity.
NOTES
args=(release create "$tag" "$asset" "$asset.sha256" --repo "$repo" --verify-tag --draft --title "Disk Assessment $version" --notes-file "$release_notes")
[[ -n "$notes_file" ]] || args+=(--generate-notes)
[[ "$prerelease" == false ]] || args+=(--prerelease)
if ! gh "${args[@]}"; then
    fail "Git tag $tag is retained. Inspect GitHub Releases for an existing/partial draft before retrying; no assets are overwritten automatically."
fi
printf 'Draft created with both assets. Review and publish it in GitHub Releases.\n'
