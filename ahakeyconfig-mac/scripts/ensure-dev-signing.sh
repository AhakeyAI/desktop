#!/bin/zsh
# 本地开发专用：确保 login keychain 里有一张稳定的自签代码签名证书。
#
# 用途：让 Debug build 的每次 codesign 都用同一个 CN 签名，
# 这样即便代码修改导致 cdhash 变化，macOS TCC 仍然按证书 CN 认
# "输入监控 / 辅助功能 / 麦克风 / 语音转写" 等授权，无需每次重新勾选。
#
# stdout: 证书 SHA-1 指纹（供 codesign --sign 使用）
# stderr: 所有进度信息
#
# 为什么输出 SHA-1 而不是 CN？
#   自签证书没系统 trust，`codesign --sign "<CN>"` 会报 "no identity found"；
#   但 `codesign --sign "<SHA-1>"` 会绕过 trust 检查、直接用私钥签。
#   签出来的 Authority 字段仍是 CN "AhaKey Local Dev"，TCC 按这个字段认，
#   所以 CN 必须稳定（不同 build 不能换名字）。
#
# 注意：
# - 不影响正式发布流程；scripts/build.sh 不会调用此脚本。
# - 证书仅在 login keychain，不向系统引入信任，也不上传任何地方。
# - 首次创建时 macOS 可能弹一次"允许 codesign 访问密钥"的提示，
#   点"总是允许"即可一劳永逸。

set -euo pipefail

CERT_CN="${AHAKEY_DEV_CERT_CN:-AhaKey Local Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 按 CN 精确匹配查 SHA-1
find_valid_sha1() {
  local cn="$1"
  security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null \
    | awk -v cn="\"$cn\"" '$0 ~ cn {print $2; exit}'
}

# 按正则匹配查第一个有效 identity（用于找 "Apple Development: ..."）
find_valid_by_pattern() {
  local pat="$1"
  security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null \
    | awk -v pat="$pat" '$0 ~ pat {print $2; exit}'
}

# 优先级 1: Apple Development 证书（来自 Xcode 登录 Apple ID 生成）
#   这是 TCC 稳定匹配的最可靠路径 —— Apple root chain 签的 app，
#   TCC 严格按 designated requirement 评估，cdhash 变也不会掉权限。
apple_dev="$(find_valid_by_pattern 'Apple Development: ')"
if [[ -n "$apple_dev" ]]; then
  >&2 echo "🍎 [ensure-dev-signing] 使用 Apple Development 证书 $apple_dev"
  echo "$apple_dev"
  exit 0
fi

# 优先级 2: 自签 AhaKey Local Dev（若已存在且受信）
valid="$(find_valid_sha1 "$CERT_CN")"
if [[ -n "$valid" ]]; then
  >&2 echo "🔏 [ensure-dev-signing] 使用自签证书 '$CERT_CN' $valid"
  >&2 echo "   提示：若之后你在 Xcode 登录 Apple ID 并生成 'Apple Development' 证书，"
  >&2 echo "   本脚本会自动切换使用它（更稳，无需操作）。"
  echo "$valid"
  exit 0
fi

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# 按 CN 精确匹配查任意状态下的 identity（含 untrusted）
find_any_sha1() {
  security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | awk -v cn="\"$CERT_CN\"" '$0 ~ cn {print $2; exit}'
}

# 情况 A：证书已在 keychain 但未受信 → 只需补信任即可，无需重新生成
untrusted="$(find_any_sha1)"
if [[ -n "$untrusted" ]]; then
  >&2 echo "🔐 [ensure-dev-signing] 发现 '$CERT_CN' 但未标记为 codesign 受信，补 trust…"
  # 导出现有证书的 PEM 供 add-trusted-cert 使用
  security find-certificate -c "$CERT_CN" -p "$KEYCHAIN" > "$TMPDIR_LOCAL/cert.pem"
else
  >&2 echo "🔐 [ensure-dev-signing] 首次创建本地自签代码签名证书 '$CERT_CN' …"

  if ! command -v openssl >/dev/null 2>&1; then
    >&2 echo "❌ 找不到 openssl，无法创建证书"
    exit 1
  fi

  # Apple code signing policy 要求：
  #   keyUsage=digitalSignature
  #   extendedKeyUsage=codeSigning
  #   basicConstraints=CA:FALSE
  # 缺任何一条 codesign 就会报 "Invalid Key Usage for policy"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$TMPDIR_LOCAL/key.pem" \
    -out "$TMPDIR_LOCAL/cert.pem" \
    -days 3650 \
    -subj "/CN=$CERT_CN" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" \
    >/dev/null 2>&1

  PFX_PASS="ahakey-dev-$(date +%s)"
  # OpenSSL 3.x 默认导出现代格式 (AES-256-CBC/PBKDF2)，
  # 但 macOS `security import` 只支持传统 PKCS#12 (RC2/3DES)。
  # `-legacy` 强制回退到传统格式。
  # LibreSSL / OpenSSL 1.1.x 不识别 -legacy，所以加 fallback。
  if ! openssl pkcs12 -export -legacy \
      -in "$TMPDIR_LOCAL/cert.pem" \
      -inkey "$TMPDIR_LOCAL/key.pem" \
      -out "$TMPDIR_LOCAL/bundle.p12" \
      -name "$CERT_CN" \
      -password "pass:$PFX_PASS" \
      >/dev/null 2>&1; then
    openssl pkcs12 -export \
      -in "$TMPDIR_LOCAL/cert.pem" \
      -inkey "$TMPDIR_LOCAL/key.pem" \
      -out "$TMPDIR_LOCAL/bundle.p12" \
      -name "$CERT_CN" \
      -password "pass:$PFX_PASS" \
      >/dev/null 2>&1
  fi

  security import "$TMPDIR_LOCAL/bundle.p12" \
    -k "$KEYCHAIN" \
    -P "$PFX_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null

  # 尝试免密授权 codesign 使用私钥；失败只是"首次签名会弹一次提示"，
  # 不影响证书本身可用性。
  security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    "$KEYCHAIN" >/dev/null 2>&1 || {
    >&2 echo "   ⚠️  未能自动授权钥匙串访问，首次签名时可能弹一次密码框，选'总是允许'即可。"
  }
fi

# 建立用户级 code signing trust —— codesign 只接受通过 policy 评估的 identity。
# 这一步会弹一次 macOS 对话框让用户用 Touch ID / 登录密码确认，
# 之后永久生效（下次 build 不会再弹）。
>&2 echo "🔑 [ensure-dev-signing] 正在把证书标记为 codesign 可信；"
>&2 echo "   macOS 会弹一次对话框，请用 Touch ID / 登录密码确认。"
if ! security add-trusted-cert -r trustRoot -p codeSign \
      -k "$KEYCHAIN" \
      "$TMPDIR_LOCAL/cert.pem" 2>>/tmp/ahakey-ensure-dev-signing.log; then
  >&2 echo "❌ add-trusted-cert 失败（看 /tmp/ahakey-ensure-dev-signing.log）"
  >&2 echo "   若刚才取消了弹窗，再次运行本脚本即可。"
  exit 1
fi

sha1="$(find_valid_sha1 "$CERT_CN")"
if [[ -z "$sha1" ]]; then
  >&2 echo "❌ 证书受信后仍无法被 codesign 识别为有效 identity"
  exit 1
fi

>&2 echo "✅ 证书 '$CERT_CN' 已就绪 (SHA-1 $sha1)，后续所有 Debug build 都会用它签名。"
echo "$sha1"
