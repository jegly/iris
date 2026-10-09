#!/usr/bin/env bash
# Iris — local TLS 1.3 test server for the post-quantum / cipher settings. Needs OpenSSL 3.5+ (ML-KEM).
# Usage: test/tls-pq-server.sh <mode> [port]     then open https://localhost:<port> in Iris (default port 8443),
# proceed past the self-signed certificate warning and check Page Info -> Connection details.
#
# Modes and what Iris should show:
#   mlkem1024  server accepts ONLY ML-KEM-1024.
#              Any Iris (CNSA preferences on): Key exchange MLKEM1024 (reached via HelloRetryRequest).
#   prefer     server accepts MLKEM1024, X25519MLKEM768, X25519 and takes a group the client already sent a key
#              share for (no HelloRetryRequest).
#              Default Iris: X25519MLKEM768.  "Strict post-quantum encryption" ON: MLKEM1024.
#   aes128     server offers ONLY TLS_AES_128_GCM_SHA256.
#              Default Iris: connects with AES-128.  "Strict post-quantum encryption" ON: connection fails
#              (ERR_SSL_VERSION_OR_CIPHER_MISMATCH).
# The server log ("Shared groups", ciphers) is printed in the page itself (-www).
# Verified 2026-10-03 with OpenSSL 3.5.5 (mlkem1024 mode also against Iris 156.0.8073.0-3: MLKEM1024).
# The "Strict post-quantum encryption" setting this script tests is compiled into Iris since release 0.0.0.4
# (patches/apply-strict-pq-tls.sh; desktop: Settings -> Privacy and security -> Iris hardening -> Network).
set -euo pipefail
MODE="${1:-}"
PORT="${2:-8443}"
case "$MODE" in
  mlkem1024) OPTS=(-groups MLKEM1024) ;;
  prefer)    OPTS=(-groups MLKEM1024:X25519MLKEM768:X25519) ;;
  aes128)    OPTS=(-ciphersuites TLS_AES_128_GCM_SHA256) ;;
  *) echo "usage: $0 mlkem1024|prefer|aes128 [port]" >&2; exit 2 ;;
esac
openssl version | grep -Eq '^OpenSSL (3\.([5-9]|[1-9][0-9])|[4-9])' ||
  { echo "ERROR: needs OpenSSL 3.5 or newer (ML-KEM); found: $(openssl version)" >&2; exit 1; }
DIR="$(mktemp -d "${TMPDIR:-/tmp}/iris-tls-test.XXXXXX")"
trap 'rm -rf "$DIR"' EXIT
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$DIR/key.pem" \
  -out "$DIR/cert.pem" -days 1 -subj /CN=localhost -addext subjectAltName=DNS:localhost 2>/dev/null
echo "Mode $MODE: open https://localhost:$PORT in Iris (Ctrl+C to stop)"
openssl s_server -accept "$PORT" -www -tls1_3 "${OPTS[@]}" -cert "$DIR/cert.pem" -key "$DIR/key.pem"
