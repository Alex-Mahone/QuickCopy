#!/bin/zsh
# 为本机创建一个固定的代码签名身份。
#
# 为什么需要：ad-hoc 签名（codesign --sign -）的 cdhash 每次编译都会变，
# 而 macOS 的辅助功能授权绑定在签名指纹上，所以每次重编都要重新授权。
# 用固定的自签证书后，App 的 designated requirement 变成
# “bundle id + 这张证书”，重编后授权仍然有效。
#
# 私钥只放在独立的钥匙串里，不碰登录钥匙串；生成的证书是自签的，
# 本地运行没有 quarantine 属性，Gatekeeper 不会拦截。
set -euo pipefail

IDENTITY="QuickCopy Local Signing"
SIGN_DIR="$HOME/Library/Application Support/QuickCopy/signing"
KEYCHAIN_DB="$SIGN_DIR/QuickCopy.keychain-db"
KEYCHAIN_PASS="quickcopy"

# 自签证书不受系统信任，find-identity 会显示 “0 valid identities”，
# 因此这里改用 find-certificate 判断身份是否已存在。
if security find-certificate -c "$IDENTITY" "$KEYCHAIN_DB" >/dev/null 2>&1; then
  echo "Signing identity already present: $IDENTITY"
  exit 0
fi

mkdir -p "$SIGN_DIR"
cd "$SIGN_DIR"

cat > openssl.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = QuickCopy Local Signing
O = QuickCopy
C = US
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

if [[ ! -f cert.pem || ! -f key.pem ]]; then
  echo "Generating self-signed code signing certificate..."
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config openssl.cnf \
    -keyout key.pem -out cert.pem >/dev/null 2>&1
fi

# LibreSSL 需要显式指定旧式 PBE 算法与 MAC digest。
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$IDENTITY" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout pass:"$KEYCHAIN_PASS" -out identity.p12 >/dev/null 2>&1

if [[ ! -f "$KEYCHAIN_DB" ]]; then
  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_DB"
fi
security set-keychain-settings "$KEYCHAIN_DB"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_DB"
security import identity.p12 -k "$KEYCHAIN_DB" -P "$KEYCHAIN_PASS" \
  -A -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASS" "$KEYCHAIN_DB" >/dev/null

echo "Installed signing identity: $IDENTITY"
echo "Keychain: $KEYCHAIN_DB"
echo "Certificate: $SIGN_DIR/cert.pem"
