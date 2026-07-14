#!/bin/bash

set -euo pipefail
umask 077

IDENTITY_NAME="ClaudeAlertBot Local Development"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SECURITY_BIN="${CAB_SECURITY_BIN:-/usr/bin/security}"
OPENSSL_BIN="${CAB_OPENSSL_BIN:-/usr/bin/openssl}"
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
    write_local_config "$fingerprint"
    echo "Reusing local signing identity: $fingerprint"
    echo "Config: $LOCAL_CONFIG"
    exit 0
fi

if "$SECURITY_BIN" find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    fail "certificate exists but is not a usable signing identity: $IDENTITY_NAME"
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-alert-bot-signing.XXXXXX")
KEY_PATH="$TEMP_DIR/local-signing.key"
CSR_PATH="$TEMP_DIR/local-signing.csr"
CERT_PATH="$TEMP_DIR/local-signing.crt"
OPENSSL_CONFIG="$TEMP_DIR/openssl.cnf"

cat > "$OPENSSL_CONFIG" <<'EOF'
[ req ]
distinguished_name = subject
prompt = no

[ subject ]
CN = ClaudeAlertBot Local Development
O = ClaudeAlertBot Local Development

[ codesign ]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

"$OPENSSL_BIN" genrsa -out "$KEY_PATH" 2048
"$OPENSSL_BIN" req -new -key "$KEY_PATH" -out "$CSR_PATH" -config "$OPENSSL_CONFIG"
serial="0x0$(/usr/bin/uuidgen | /usr/bin/tr -d '-')"
"$OPENSSL_BIN" x509 -req -sha256 -days 3650 \
    -set_serial "$serial" \
    -in "$CSR_PATH" -signkey "$KEY_PATH" \
    -out "$CERT_PATH" -extfile "$OPENSSL_CONFIG" -extensions codesign

certificate_text=$("$OPENSSL_BIN" x509 -in "$CERT_PATH" -noout -text)
[[ "$certificate_text" == *"CA:TRUE, pathlen:0"* ]] || fail "generated certificate is not a constrained root"
[[ "$certificate_text" == *"Digital Signature"* ]] || fail "generated certificate lacks digitalSignature usage"
[[ "$certificate_text" == *"Certificate Sign"* ]] || fail "generated certificate lacks keyCertSign usage"
[[ "$certificate_text" == *"Code Signing"* ]] || fail "generated certificate lacks codeSigning usage"

fingerprint_output=$("$OPENSSL_BIN" x509 -in "$CERT_PATH" -noout -fingerprint -sha1)
fingerprint=$(normalize_fingerprint "${fingerprint_output#*=}")
is_valid_fingerprint "$fingerprint" || fail "could not read generated certificate fingerprint"

"$SECURITY_BIN" add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN_PATH" "$CERT_PATH"
"$SECURITY_BIN" import "$KEY_PATH" -k "$KEYCHAIN_PATH" -f openssl -t priv -T /usr/bin/codesign

fingerprints=$(exact_identity_fingerprints)
identity_count=$(exact_identity_count "$fingerprints")
if [[ "$identity_count" -ne 1 ]] || ! identity_available "$fingerprint"; then
    fail "created certificate is not available as the expected signing identity"
fi

write_local_config "$fingerprint"
echo "Created local signing identity: $fingerprint"
echo "Config: $LOCAL_CONFIG"
echo "Next: xcodegen generate && scripts/build.sh"
