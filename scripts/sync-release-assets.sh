#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-samqin123/MoonTV}"
TARGET_REPO="${TARGET_REPO:-KUAILESHANGWEI/MoonTV}"

for required_command in gh jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is required." >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

tag_name="$(gh release list --repo "$UPSTREAM_REPO" --exclude-drafts --limit 1 --json tagName --jq '.[0].tagName // empty')"
if [[ -z "$tag_name" ]]; then
  echo "No upstream release found for $UPSTREAM_REPO; nothing to sync."
  exit 0
fi

release_json="$tmp_dir/release.json"
gh release view "$tag_name" --repo "$UPSTREAM_REPO" --json tagName,name,body,isDraft,isPrerelease >"$release_json"

release_name="$(jq -r '.name // .tagName' "$release_json")"
is_prerelease="$(jq -r '.isPrerelease' "$release_json")"
release_body_file="$tmp_dir/release-body.md"
jq -r '.body // ""' "$release_json" >"$release_body_file"

verify_tag_args=()
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git remote remove upstream-release >/dev/null 2>&1 || true
  git remote add upstream-release "https://github.com/${UPSTREAM_REPO}.git"
  git fetch upstream-release "+refs/tags/${tag_name}:refs/tags/${tag_name}"
  git push --force origin "refs/tags/${tag_name}:refs/tags/${tag_name}"
  verify_tag_args=(--verify-tag)
fi

asset_dir="$tmp_dir/assets"
mkdir -p "$asset_dir"
upstream_assets=()
while IFS= read -r asset_name; do
  upstream_assets+=("$asset_name")
done < <(gh release view "$tag_name" --repo "$UPSTREAM_REPO" --json assets --jq '.assets[].name')

if ((${#upstream_assets[@]} > 0)); then
  gh release download "$tag_name" --repo "$UPSTREAM_REPO" --dir "$asset_dir" --clobber
fi

release_flags=(--repo "$TARGET_REPO" --title "$release_name" --notes-file "$release_body_file" --latest)
if [[ "$is_prerelease" == "true" ]]; then
  release_flags+=(--prerelease)
fi

if gh release view "$tag_name" --repo "$TARGET_REPO" >/dev/null 2>&1; then
  gh release edit "$tag_name" "${release_flags[@]}"
else
  gh release create "$tag_name" "${release_flags[@]}" "${verify_tag_args[@]}"
fi

target_assets=()
while IFS= read -r asset_name; do
  target_assets+=("$asset_name")
done < <(gh release view "$tag_name" --repo "$TARGET_REPO" --json assets --jq '.assets[].name')
for target_asset in "${target_assets[@]}"; do
  keep_asset=false
  for upstream_asset in "${upstream_assets[@]}"; do
    if [[ "$target_asset" == "$upstream_asset" ]]; then
      keep_asset=true
      break
    fi
  done

  if [[ "$keep_asset" == false ]]; then
    gh release delete-asset "$tag_name" "$target_asset" --repo "$TARGET_REPO" --yes
  fi
done

if ((${#upstream_assets[@]} > 0)); then
  gh release upload "$tag_name" "$asset_dir"/* --repo "$TARGET_REPO" --clobber
fi

echo "Synced release $tag_name from $UPSTREAM_REPO to $TARGET_REPO."
