#!/usr/bin/env bash

#
# Generate the tiny one-step IMEI bootstrap launcher.
# The launcher is intended to be hosted at a stable URL such as dist.1-2.dev/imei.sh
# so download counts remain visible there, while the actual runtime is fetched from
# the signed GitHub release bundle before execution.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_PATH="${1:-$REPO_ROOT/dist/imei-bootstrap.sh}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

cat >"$OUTPUT_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

DEFAULT_GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-SoftCreatR/imei}"
GITHUB_REPOSITORY="$DEFAULT_GITHUB_REPOSITORY"
RELEASE_TAG=""
DOWNLOAD_DIR=""
FORWARDED_ARGS=("$@")
WORK_DIR=""
KEYRING_DIR=""

die() {
  echo "Error: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

github_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s\n' "$GH_TOKEN"
    return 0
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s\n' "$GITHUB_TOKEN"
    return 0
  fi

  return 1
}

fetch_file() {
  local url="$1"
  local output_path="$2"

  if command_exists curl; then
    curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output_path" 2>/dev/null
    return $?
  fi

  if command_exists wget; then
    wget -qO "$output_path" "$url" 2>/dev/null
    return $?
  fi

  die "Neither curl nor wget is available."
}

fetch_release_asset() {
  local base_url="$1"
  local asset_name="$2"
  local output_path="$3"
  local asset_url="$base_url/$asset_name"
  local token=""

  if token="$(github_token)"; then
    if curl -fsSL --retry 3 --retry-delay 1 \
      -H "Authorization: Bearer $token" \
      "$asset_url" \
      -o "$output_path" \
      2>/dev/null; then
      return 0
    fi
  elif fetch_file "$asset_url" "$output_path"; then
    return 0
  fi

  return 1
}

release_download_base() {
  if [[ -n "$RELEASE_TAG" ]]; then
    printf 'https://github.com/%s/releases/download/%s\n' "$GITHUB_REPOSITORY" "$RELEASE_TAG"
  else
    printf 'https://github.com/%s/releases/latest/download\n' "$GITHUB_REPOSITORY"
  fi
}

verify_signature() {
  local file_path="$1"
  local signature_path="$2"
  local key_id_path="$3"
  local key_id
  local public_key_path

  command_exists openssl || die "openssl is required for bootstrap signature verification."
  key_id="$(tr -d '\n' <"$key_id_path")"
  public_key_path="$KEYRING_DIR/$key_id.pem"
  [[ -f "$public_key_path" ]] || die "bootstrap keyring does not contain signer key '$key_id'"

  openssl dgst -sha512 -verify "$public_key_path" -signature "$signature_path" "$file_path" >/dev/null
}

download_repository_checkout() {
  local archive_path="$WORK_DIR/repository.tar.gz"
  local extract_dir="$WORK_DIR/repository"
  local source_root

  echo "Release runtime bundle unavailable. Falling back to repository checkout from $GITHUB_REPOSITORY/main." >&2
  fetch_file "https://github.com/$GITHUB_REPOSITORY/archive/refs/heads/main.tar.gz" "$archive_path" || die "failed to download repository source archive"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xzf "$archive_path" -C "$extract_dir"

  source_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$source_root" ]] || die "repository source archive did not extract correctly"

  exec bash "$source_root/imei.sh" "${FORWARDED_ARGS[@]}"
}

write_embedded_keyring() {
  mkdir -p "$KEYRING_DIR"
EOF

for key_path in "$REPO_ROOT"/keys/*.pem; do
  key_name="$(basename "$key_path")"
  case "$key_name" in
  private-*) continue ;;
  esac

  safe_marker="$(printf '%s' "$key_name" | tr '.-' '__')"
  {
    printf "  cat >\"\$KEYRING_DIR/%s\" <<'EOF_%s'\n" "$key_name" "$safe_marker"
    cat "$key_path"
    printf "\nEOF_%s\n" "$safe_marker"
  } >>"$OUTPUT_PATH"
done

{
  cat <<'EOF'
  cat >"$KEYRING_DIR/active.key" <<'EOF_ACTIVE_KEY'
EOF
  cat "$REPO_ROOT/keys/active.key"
  cat <<'EOF'
EOF_ACTIVE_KEY
}

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" && -z "$DOWNLOAD_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --github-repository)
    GITHUB_REPOSITORY="$2"
    shift 2
    ;;
  --release-tag)
    RELEASE_TAG="$2"
    shift 2
    ;;
  --download-dir)
    DOWNLOAD_DIR="$2"
    shift 2
    ;;
  *)
    shift
    ;;
  esac
done

if [[ -n "$DOWNLOAD_DIR" ]]; then
  mkdir -p "$DOWNLOAD_DIR"
  WORK_DIR="$DOWNLOAD_DIR"
else
  WORK_DIR="$(mktemp -d)"
fi

KEYRING_DIR="$WORK_DIR/keys"
write_embedded_keyring
trap cleanup EXIT

BUNDLE_PATH="$WORK_DIR/imei-update.tar.gz"
BUNDLE_SIG_PATH="$WORK_DIR/imei-update.tar.gz.sig"
BUNDLE_SIG_KEY_PATH="$WORK_DIR/imei-update.tar.gz.sig.key"
BUNDLE_EXTRACT_DIR="$WORK_DIR/imei-update"
BASE_URL="$(release_download_base)"

if ! fetch_release_asset "$BASE_URL" "imei-update.tar.gz" "$BUNDLE_PATH" 2>/dev/null; then
  download_repository_checkout
fi

if ! fetch_release_asset "$BASE_URL" "imei-update.tar.gz.sig" "$BUNDLE_SIG_PATH" 2>/dev/null; then
  download_repository_checkout
fi

if ! fetch_release_asset "$BASE_URL" "imei-update.tar.gz.sig.key" "$BUNDLE_SIG_KEY_PATH" 2>/dev/null; then
  download_repository_checkout
fi

if ! verify_signature "$BUNDLE_PATH" "$BUNDLE_SIG_PATH" "$BUNDLE_SIG_KEY_PATH"; then
  die "downloaded update bundle signature verification failed"
fi

rm -rf "$BUNDLE_EXTRACT_DIR"
mkdir -p "$BUNDLE_EXTRACT_DIR"
tar -xzf "$BUNDLE_PATH" -C "$BUNDLE_EXTRACT_DIR"

exec bash "$BUNDLE_EXTRACT_DIR/imei.sh" "${FORWARDED_ARGS[@]}"
EOF
} >>"$OUTPUT_PATH"
chmod 0755 "$OUTPUT_PATH"
