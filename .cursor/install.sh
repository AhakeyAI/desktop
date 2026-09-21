#!/usr/bin/env bash
#
# Cloud Agent install script for the AhaKey Desktop repository.
#
# Scope: build and debug the WINDOWS desktop client (`ahakeyconfig-win-java/`,
# Java 17 + JavaFX, Maven) on the Linux Cloud Agent VM.
#
# Why this works on Linux even though it is the "Windows" client:
#   * It is plain Java/JavaFX bytecode built with Maven, so the produced jar is
#     the same one that runs on Windows. Maven auto-resolves the Linux JavaFX
#     natives, so the GUI can be launched and debugged here on the VNC desktop.
#
# What is NOT possible on a Linux VM (and is intentionally out of scope here):
#   * Producing/running a native Windows .exe / installer
#     (build-exe.ps1, build-installer.ps1, Inno Setup, jpackage-on-Windows).
#   * Exercising the Windows-only JNA paths at runtime
#     (src/main/java/com/example/ahakey/platform/windows/*, Win+H voice,
#     low-level keyboard hook). They still COMPILE fine here.
#
# The macOS client (Swift/SwiftUI) requires a macOS runner and is out of scope.
#
# This script is idempotent and safe to re-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WIN_JAVA_DIR="ahakeyconfig-win-java"

echo "==> AhaKey Desktop install: preparing the Windows Java client toolchain"

# --- System packages -------------------------------------------------------
# Maven builds the client (the pre-installed JDK 21 compiles the Java 17 target).
# The remaining libraries are only needed to *launch* the JavaFX GUI on the
# Linux desktop; they are not required merely to compile. Only touch apt when
# something is actually missing so re-runs stay fast.
gui_lib_present() { ldconfig -p 2>/dev/null | grep -q "$1"; }

need_apt=0
command -v mvn >/dev/null 2>&1 || need_apt=1
gui_lib_present libgtk-3.so.0 || need_apt=1
gui_lib_present libGL.so.1    || need_apt=1
command -v xvfb-run >/dev/null 2>&1 || need_apt=1

if [ "$need_apt" -eq 1 ]; then
  echo "==> Installing system packages (maven + JavaFX GUI runtime libs + xvfb)"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends \
    maven \
    libgtk-3-0 libglib2.0-0 libgl1 \
    libxtst6 libxrender1 libxi6 libxext6 libxxf86vm1 \
    xvfb fonts-dejavu-core
else
  echo "==> System packages already present (maven, GTK/GL, xvfb)"
fi

# --- Build the Windows Java client -----------------------------------------
echo "==> Building $WIN_JAVA_DIR (mvn package, tests skipped)"
mvn -f "$WIN_JAVA_DIR/pom.xml" -B -DskipTests package

JAR="$WIN_JAVA_DIR/target/ahakey-studio-1.0.0.jar"
if [ -f "$JAR" ]; then
  echo "==> Build artifact: $JAR"
  echo "==> Runtime libs copied: $(ls "$WIN_JAVA_DIR/target/lib" | wc -l) jars (incl. javafx-*-linux)"
else
  echo "!! Expected jar not found: $JAR" >&2
  exit 1
fi

echo "==> Toolchain versions:"
echo "    java : $(java -version 2>&1 | head -n1)"
echo "    mvn  : $(mvn -v 2>&1 | head -n1)"

cat <<'EOF'
==> Install complete.

Run / debug the Windows client GUI on the Cloud Agent's VNC desktop:

    cd ahakeyconfig-win-java
    DISPLAY=:1 java -cp "target/ahakey-studio-1.0.0.jar:target/lib/*" \
      com.example.ahakey.Main

Or headless (no desktop) under a virtual X server:

    cd ahakeyconfig-win-java
    xvfb-run -a java -cp "target/ahakey-studio-1.0.0.jar:target/lib/*" \
      com.example.ahakey.Main

Note: without an AhaKey device / BLE-TCP bridge the app runs but shows
"未连接" (disconnected); the lever fail-safe defaults to "ask".
EOF
