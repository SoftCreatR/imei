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
  cat >"$KEYRING_DIR/20230505.pem" <<'EOF_20230505_pem'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxpamXHkhQvgQfgLxJmIk
4JmDHc5PhTeHSSM+SUCLkrgL+nW0uRjppWaMrfzVI2glYSqb5xDJqgoArdhLcyo4
Zt+mOXHuBU3X1cKxaDqGWgrpTIHooHVrJ+hIUqTJ0qIiWPLXNes6LUMAF/FPxtTB
enbqVVLr/64VzoviE2odaLaeH8c+iW+IIlPf6AO9GrZSeNjCcfv2lHpk/AqlNkuW
wr9ihbRt6a49Jhedel8d3pM74qMjSFkzNSQstE+Jiyh1lb+b5a1mgHy0ckKJnayt
37rgl22/IYrd4EGrlu0FRjZBqlDDjtL5kIgt/gA3dCTHgzdcVutaLpTHBIz9qcR+
AT7bPcBrt22hsFYnpuRBgVRapr0fa2IqhDi6am1UDLtIj+LTYcotoMc9z6en3jUC
MwjiMVcUfGQqjjFQ+QhHV24QcWrrzx3zpBy0PUuB84qpTaBB5BdG4R9SUZ+Nnd1u
KDH15+JTAcE29Ouv0mhD2v23udjpfITacvfgbsvmOsuxq4GqsPJoH63EYARiNYsw
BLDsJHDVmvsr/BXX0sSbHR7xDDITMihZHk4V5wVCjvvcEehwMidaIUgqENJADtgN
4olFN9zS7tat7qIqb9myzjCTnS6TWOlOaDzBeLKV6PTSZuErGW55XhOocfDQojol
qjLZb1NuMCrRJIok1rOesDMCAwEAAQ==
-----END PUBLIC KEY-----

EOF_20230505_pem
  cat >"$KEYRING_DIR/20260323.pem" <<'EOF_20260323_pem'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvTLOLbvzAuWJ5lJycDFw
AaYZWCW4BHxaoA78dptBnY099CTBEZa1WNT3Ipn3YQMHqnD8XQldVGID2Z1KEnhH
0iTu5pGtO3HOiZPE2VaPac0uof5HkJVmi9u3v316OP2H4cJanEVTYi5PhVRgI6/I
Q162lOsSTDF0ahOusOYyeCAXXdmNMg3kIkGFgi7BXIjA9A47MW1fuosA8/NzCIAb
y+qd8p8gd4jOqlK7EfeMo4mP6leKj1uKkJCeMe5z8U+jk7fbC7W7qrxj3Vg5kLPS
PKKnY0g9c/Ibfvaob2XSYbvtdnqCtmQ4sWQkH9jNSaSiZwPN1iMXd52lCIHMnRic
IJ+tFS5R8M7QgvZPauQPh/PyTCj/s0PSAOz9Ymb12QclMty22gbJIFcCcVr7TRdv
CKvu5eyZubyPTIUmUzP3OI1DOERfdoyvp9L3KJIHE+ViTgZ8KMVMTxsGRzda8lVz
oFTKpWn2sMf/VRNtDNPiaSbowQfDC1/khH64Dce2iqhghEMROSzNLho4/cTMqvh0
SsE2ex0F5l9VlRcjaoe9OBfanfI+MqIbSarFnpUqTW7XKR9797NOz5CBdYAPf9LY
bAB9vsEFgRIxkWQnT0WydYhVY9qib4MjJjfPyF2AxvXBZW+rqV55y3rVE32D9gMi
/KMkWaMa0U+kvol2vFu7hG0CAwEAAQ==
-----END PUBLIC KEY-----

EOF_20260323_pem
  cat >"$KEYRING_DIR/active.key" <<'EOF_ACTIVE_KEY'
20260323
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
