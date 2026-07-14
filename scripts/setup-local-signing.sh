#!/bin/bash

set -euo pipefail
umask 077

ROOT_IDENTITY_NAME="ClaudeAlertBot Local Root CA v2"
IDENTITY_NAME="ClaudeAlertBot Local Development v2"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SECURITY_BIN="${CAB_SECURITY_BIN:-/usr/bin/security}"
OPENSSL_BIN="${CAB_OPENSSL_BIN:-/usr/bin/openssl}"
CODESIGN_BIN="${CAB_CODESIGN_BIN:-/usr/bin/codesign}"
KEYCHAIN_PATH="${CAB_KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
LOCAL_CONFIG="${CAB_LOCAL_SIGNING_CONFIG_PATH:-$ROOT/Config/LocalSigning.xcconfig}"

TEMP_DIR=""
CONFIG_TEMP=""

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ -n "$CONFIG_TEMP" && -f "$CONFIG_TEMP" ]]; then
        rm -f "$CONFIG_TEMP"
    fi
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

normalize_fingerprint() {
    printf '%s' "$1" | /usr/bin/tr -d ':' | /usr/bin/tr '[:lower:]' '[:upper:]'
}

is_valid_fingerprint() {
    [[ "$1" =~ ^[0-9A-F]{40}$ ]]
}

identity_output() {
    "$SECURITY_BIN" find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null || true
}

exact_identity_fingerprints() {
    local output line fingerprint
    output=$(identity_output)
    while IFS= read -r line; do
        if [[ "$line" == *"\"$IDENTITY_NAME\"" ]]; then
            fingerprint=$(normalize_fingerprint "$(printf '%s\n' "$line" | /usr/bin/awk '{print $2}')")
            if is_valid_fingerprint "$fingerprint"; then
                printf '%s\n' "$fingerprint"
            fi
        fi
    done <<< "$output"
}

identity_available() {
    local expected="$1"
    local output line fingerprint
    output=$(identity_output)
    while IFS= read -r line; do
        if [[ "$line" == *"\"$IDENTITY_NAME\"" ]]; then
            fingerprint=$(normalize_fingerprint "$(printf '%s\n' "$line" | /usr/bin/awk '{print $2}')")
            if [[ "$fingerprint" == "$expected" ]]; then
                return 0
            fi
        fi
    done <<< "$output"
    return 1
}

exact_identity_count() {
    local fingerprints="$1"
    if [[ -z "$fingerprints" ]]; then
        printf '0'
    else
        printf '%s\n' "$fingerprints" | /usr/bin/awk 'NF { count++ } END { print count + 0 }'
    fi
}

config_value() {
    local key="$1"
    local path="$2"
    /usr/bin/awk -v key="$key" '
        {
            separator = index($0, "=")
            if (separator == 0) next
            name = substr($0, 1, separator - 1)
            gsub(/^[ \t]+|[ \t]+$/, "", name)
            if (name != key) next
            value = substr($0, separator + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", value)
            print value
            exit
        }
    ' "$path"
}

write_local_config() {
    local fingerprint="$1"
    local config_dir
    config_dir=$(dirname "$LOCAL_CONFIG")
    mkdir -p "$config_dir"
    CONFIG_TEMP=$(mktemp "$config_dir/.LocalSigning.xcconfig.XXXXXX")
    {
        printf 'CAB_CODE_SIGN_IDENTITY = %s\n' "$fingerprint"
        printf 'CAB_CODE_SIGN_KEYCHAIN = %s\n' "$KEYCHAIN_PATH"
        printf 'OTHER_CODE_SIGN_FLAGS = --keychain "$(CAB_CODE_SIGN_KEYCHAIN)"\n'
    } > "$CONFIG_TEMP"
    mv "$CONFIG_TEMP" "$LOCAL_CONFIG"
    CONFIG_TEMP=""
}

verify_signing_identity() {
    local fingerprint="$1"
    if [[ -z "$TEMP_DIR" ]]; then
        TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-alert-bot-signing.XXXXXX")
    fi
    local probe_path="$TEMP_DIR/signing-probe"
    /bin/cp /usr/bin/true "$probe_path"
    "$CODESIGN_BIN" --force --sign "$fingerprint" --keychain "$KEYCHAIN_PATH" "$probe_path" >/dev/null
    "$CODESIGN_BIN" --verify --verbose=2 "$probe_path" >/dev/null
}

show_status() {
    local fingerprint configured_keychain
    if [[ ! -f "$LOCAL_CONFIG" ]]; then
        echo "Local signing is not configured: $LOCAL_CONFIG" >&2
        exit 1
    fi

    fingerprint=$(normalize_fingerprint "$(config_value CAB_CODE_SIGN_IDENTITY "$LOCAL_CONFIG")")
    if ! is_valid_fingerprint "$fingerprint"; then
        fail "local signing config has an invalid certificate fingerprint"
    fi

    configured_keychain=$(config_value CAB_CODE_SIGN_KEYCHAIN "$LOCAL_CONFIG")
    if [[ -n "$configured_keychain" ]]; then
        KEYCHAIN_PATH="$configured_keychain"
    fi

    if ! identity_available "$fingerprint"; then
        fail "configured identity is unavailable in Keychain: $KEYCHAIN_PATH"
    fi

    echo "Local signing is configured and usable."
    echo "Identity: $fingerprint"
    echo "Keychain: $KEYCHAIN_PATH"
}

if [[ "${1:-}" == "--status" ]]; then
    show_status
    exit 0
fi
if [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--status]" >&2
    exit 64
fi

fingerprints=$(exact_identity_fingerprints)
identity_count=$(exact_identity_count "$fingerprints")

if [[ "$identity_count" -gt 1 ]]; then
    fail "multiple exact signing identities named '$IDENTITY_NAME' exist in $KEYCHAIN_PATH"
fi

if [[ "$identity_count" -eq 1 ]]; then
    fingerprint=$(printf '%s\n' "$fingerprints" | /usr/bin/awk 'NF { print; exit }')
    verify_signing_identity "$fingerprint"
    write_local_config "$fingerprint"
    echo "Reusing local signing identity: $fingerprint"
    echo "Config: $LOCAL_CONFIG"
    exit 0
fi

if "$SECURITY_BIN" find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    fail "certificate exists but is not a usable signing identity: $IDENTITY_NAME"
fi
if "$SECURITY_BIN" find-certificate -c "$ROOT_IDENTITY_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    fail "root certificate exists without a usable signing identity: $ROOT_IDENTITY_NAME"
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-alert-bot-signing.XXXXXX")
ROOT_KEY_PATH="$TEMP_DIR/local-root.key"
ROOT_CERT_PATH="$TEMP_DIR/local-root.crt"
LEAF_KEY_PATH="$TEMP_DIR/local-signing.key"
LEAF_CSR_PATH="$TEMP_DIR/local-signing.csr"
LEAF_CERT_PATH="$TEMP_DIR/local-signing.crt"
OPENSSL_CONFIG="$TEMP_DIR/openssl.cnf"

cat > "$OPENSSL_CONFIG" <<'EOF'
[ req ]
distinguished_name = root_subject
prompt = no

[ root_subject ]
CN = ClaudeAlertBot Local Root CA v2
O = ClaudeAlertBot Local Development

[ root_ca ]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always

[ leaf_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

"$OPENSSL_BIN" genrsa -out "$ROOT_KEY_PATH" 2048
"$OPENSSL_BIN" req -x509 -new -sha256 -days 3650 \
    -key "$ROOT_KEY_PATH" -out "$ROOT_CERT_PATH" \
    -config "$OPENSSL_CONFIG" -extensions root_ca

"$OPENSSL_BIN" genrsa -out "$LEAF_KEY_PATH" 2048
"$OPENSSL_BIN" req -new -key "$LEAF_KEY_PATH" -out "$LEAF_CSR_PATH" \
    -subj "/CN=ClaudeAlertBot Local Development v2/O=ClaudeAlertBot Local Development"
serial="0x0$(/usr/bin/uuidgen | /usr/bin/tr -d '-')"
"$OPENSSL_BIN" x509 -req -sha256 -days 3650 \
    -set_serial "$serial" \
    -in "$LEAF_CSR_PATH" -CA "$ROOT_CERT_PATH" -CAkey "$ROOT_KEY_PATH" \
    -out "$LEAF_CERT_PATH" -extfile "$OPENSSL_CONFIG" -extensions leaf_codesign

root_certificate_text=$("$OPENSSL_BIN" x509 -in "$ROOT_CERT_PATH" -noout -text)
[[ "$root_certificate_text" == *"CA:TRUE, pathlen:0"* ]] || fail "generated root certificate is not a constrained CA"
[[ "$root_certificate_text" == *"Certificate Sign"* ]] || fail "generated root certificate lacks keyCertSign usage"

leaf_certificate_text=$("$OPENSSL_BIN" x509 -in "$LEAF_CERT_PATH" -noout -text)
[[ "$leaf_certificate_text" == *"CA:FALSE"* ]] || fail "generated signing certificate is not a leaf"
[[ "$leaf_certificate_text" == *"Digital Signature"* ]] || fail "generated signing certificate lacks digitalSignature usage"
[[ "$leaf_certificate_text" == *"Code Signing"* ]] || fail "generated signing certificate lacks codeSigning usage"

fingerprint_output=$("$OPENSSL_BIN" x509 -in "$LEAF_CERT_PATH" -noout -fingerprint -sha1)
fingerprint=$(normalize_fingerprint "${fingerprint_output#*=}")
is_valid_fingerprint "$fingerprint" || fail "could not read generated certificate fingerprint"

"$SECURITY_BIN" add-trusted-cert -r trustRoot -k "$KEYCHAIN_PATH" "$ROOT_CERT_PATH"
"$SECURITY_BIN" import "$LEAF_CERT_PATH" -k "$KEYCHAIN_PATH" -f openssl -t cert
"$SECURITY_BIN" import "$LEAF_KEY_PATH" -k "$KEYCHAIN_PATH" -f openssl -t priv -T /usr/bin/codesign

fingerprints=$(exact_identity_fingerprints)
identity_count=$(exact_identity_count "$fingerprints")
if [[ "$identity_count" -ne 1 ]] || ! identity_available "$fingerprint"; then
    fail "created certificate is not available as the expected signing identity"
fi

verify_signing_identity "$fingerprint"
write_local_config "$fingerprint"
echo "Created local signing identity: $fingerprint"
echo "Config: $LOCAL_CONFIG"
echo "Next: xcodegen generate && scripts/build.sh"
