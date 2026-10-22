#!/usr/bin/env bash
# CI/local review artifact: use the complete App + Agent assembly path.
# APP_VERSION and APP_BUILD retain this entry point's version overrides.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Never install/launch or consume a local signing identity from this CI entry.
exec env \
  APP_VERSION="${APP_VERSION:-0.0.0}" \
  BUILD_ARCHS="${BUILD_ARCHS:-$(uname -m)}" \
  OUTPUT_DIR="$APP_ROOT/dist" \
  APP_BUNDLE_NAME="AhaKey Studio" \
  SIGNING_IDENTITY=- REQUIRE_DEVELOPER_ID=0 \
  INSTALL_TO_APPLICATIONS=0 LAUNCH_AFTER_INSTALL=0 \
  /bin/zsh "$SCRIPT_DIR/build.sh"
