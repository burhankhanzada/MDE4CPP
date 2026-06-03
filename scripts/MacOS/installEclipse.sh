#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# installEclipse.sh — Download Eclipse Modeling Tools and install required
# plugins (Acceleo, Sirius, CDT) for MDE4CPP on macOS.
#
# Required environment variables (set by Gradle runInstallScripts):
#   MDE4CPP_HOME
#   MDE4CPP_ECLIPSE_VERSION
#   MDE4CPP_ECLIPSE_MILESTONE
#   MDE4CPP_ECLIPSE_ACCELEO_VERSION
#   MDE4CPP_ECLIPSE_SIRIUS_VERSION
#   MDE4CPP_ECLIPSE_SIRIUS_ECLIPSE_VERSION
#
# Optional:
#   MDE4CPP_ECLIPSE_HOME — overrides default Eclipse install location.
#                          Defaults to /Applications/Eclipse.app/Contents/Eclipse
# =============================================================================

echo "[installEclipse] MDE4CPP_ECLIPSE_VERSION=${MDE4CPP_ECLIPSE_VERSION:-}"
echo "[installEclipse] MDE4CPP_ECLIPSE_MILESTONE=${MDE4CPP_ECLIPSE_MILESTONE:-}"
echo "[installEclipse] MDE4CPP_ECLIPSE_ACCELEO_VERSION=${MDE4CPP_ECLIPSE_ACCELEO_VERSION:-}"
echo "[installEclipse] MDE4CPP_ECLIPSE_SIRIUS_VERSION=${MDE4CPP_ECLIPSE_SIRIUS_VERSION:-}"
echo "[installEclipse] MDE4CPP_ECLIPSE_SIRIUS_ECLIPSE_VERSION=${MDE4CPP_ECLIPSE_SIRIUS_ECLIPSE_VERSION:-}"

# ── Step 1: Validate required environment variables ──────────────────────────

for var in MDE4CPP_HOME MDE4CPP_ECLIPSE_VERSION MDE4CPP_ECLIPSE_MILESTONE \
           MDE4CPP_ECLIPSE_ACCELEO_VERSION MDE4CPP_ECLIPSE_SIRIUS_VERSION \
           MDE4CPP_ECLIPSE_SIRIUS_ECLIPSE_VERSION; do
  if [[ -z "${!var:-}" ]]; then
    echo "[installEclipse] ERROR: ${var} is not set."
    exit 1
  fi
done

# ── Step 2: Resolve installation paths ───────────────────────────────────────
#
# MDE4CPP_ECLIPSE_HOME (set in macos_setenv.sh) points to the Eclipse plugins
# directory inside the .app bundle:
#   /Applications/Eclipse.app/Contents/Eclipse
#
# We derive all paths from it so the install script and macos_setenv.sh stay
# in sync without using relative paths.

if [[ -n "${MDE4CPP_ECLIPSE_HOME:-}" ]]; then
  # e.g. /Applications/Eclipse.app/Contents/Eclipse → /Applications/Eclipse.app
  ECLIPSE_APP_DIR="$(dirname "$(dirname "${MDE4CPP_ECLIPSE_HOME}")")"
  ECLIPSE_HOME="${MDE4CPP_ECLIPSE_HOME}"
else
  ECLIPSE_APP_DIR="/Applications/Eclipse.app"
  ECLIPSE_HOME="${ECLIPSE_APP_DIR}/Contents/Eclipse"
fi

ECLIPSE_BIN="${ECLIPSE_APP_DIR}/Contents/MacOS/eclipse"
EXTRACT_DIR="$(dirname "${ECLIPSE_APP_DIR}")"

ARCH_SUFFIX="x86_64"
if [[ "$(uname -m)" == "arm64" ]]; then
  ARCH_SUFFIX="aarch64"
fi

# Strip whitespace from version variables for URL construction.
_VER="${MDE4CPP_ECLIPSE_VERSION//[[:space:]]/}"
_MS="${MDE4CPP_ECLIPSE_MILESTONE//[[:space:]]/}"
_ACC="${MDE4CPP_ECLIPSE_ACCELEO_VERSION//[[:space:]]/}"
_SIR="${MDE4CPP_ECLIPSE_SIRIUS_VERSION//[[:space:]]/}"
_SIRE="${MDE4CPP_ECLIPSE_SIRIUS_ECLIPSE_VERSION//[[:space:]]/}"

ECLIPSE_ARCHIVE_URL="https://ftp.halifax.rwth-aachen.de/eclipse/technology/epp/downloads/release/${_VER}/${_MS}/eclipse-modeling-${_VER}-${_MS}-macosx-cocoa-${ARCH_SUFFIX}.tar.gz"
ACCELEO_REPO_URL="https://download.eclipse.org/acceleo/updates/releases/${_ACC}"
SIRIUS_REPO_URL="https://download.eclipse.org/sirius/updates/releases/${_SIR}/${_SIRE}"
RELEASES_REPO_URL="https://download.eclipse.org/releases/${_VER}"
CDT_REPO_URL="${RELEASES_REPO_URL}"

TMP_DIR="$(mktemp -d)"
ARCHIVE_PATH="${TMP_DIR}/eclipse-modeling.tar.gz"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

echo "[installEclipse] Eclipse.app location : ${ECLIPSE_APP_DIR}"
echo "[installEclipse] Eclipse home (plugins): ${ECLIPSE_HOME}"

# ── Step 3: Check for existing installation ──────────────────────────────────

NEEDS_DOWNLOAD=1

if [[ -x "${ECLIPSE_BIN}" ]]; then
  echo "[installEclipse] Existing Eclipse found at ${ECLIPSE_APP_DIR}."

  # List installed IUs to check plugin versions.
  "${ECLIPSE_BIN}" -nosplash \
    -application org.eclipse.equinox.p2.director \
    -destination "${ECLIPSE_HOME}" \
    -listInstalledRoots > "${TMP_DIR}/installed.txt" 2>&1 || true

  acceleo_installed=$(awk -F'/' '/^org\.eclipse\.acceleo\.feature\.group\// {print $2; exit}' "${TMP_DIR}/installed.txt" 2>/dev/null || true)
  sirius_installed=$(awk -F'/' '/^org\.eclipse\.sirius\.aql\.feature\.group\// {print $2; exit}' "${TMP_DIR}/installed.txt" 2>/dev/null || true)
  cdt_installed=$(awk -F'/' '/^org\.eclipse\.cdt\.feature\.group\// {print $2; exit}' "${TMP_DIR}/installed.txt" 2>/dev/null || true)

  echo "[installEclipse] Installed Acceleo : ${acceleo_installed:-<not found>}"
  echo "[installEclipse] Installed Sirius  : ${sirius_installed:-<not found>}"
  echo "[installEclipse] Installed CDT     : ${cdt_installed:-<not found>}"

  # Check all three plugins are present with the expected version prefixes.
  if [[ -n "${acceleo_installed}" && "${acceleo_installed}" == "${_ACC}"* ]] \
  && [[ -n "${sirius_installed}"  && "${sirius_installed}"  == "${_SIR}"* ]] \
  && [[ -n "${cdt_installed}" ]]; then
    echo "[installEclipse] All required plugins are already installed. Skipping."
    exit 0
  fi

  echo "[installEclipse] Some plugins are missing or have wrong versions. Will install plugins into existing Eclipse."
  NEEDS_DOWNLOAD=0
fi

# ── Step 4: Download and extract Eclipse ─────────────────────────────────────

if [[ "${NEEDS_DOWNLOAD}" == "1" ]]; then
  echo "[installEclipse] Downloading Eclipse from ${ECLIPSE_ARCHIVE_URL}"

  if command -v curl >/dev/null 2>&1; then
    curl -fL "${ECLIPSE_ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${ARCHIVE_PATH}" "${ECLIPSE_ARCHIVE_URL}"
  else
    echo "[installEclipse] ERROR: Neither curl nor wget is available."
    exit 1
  fi

  # Remove any previous installation and extract.
  # The macOS tarball contains Eclipse.app/ at its root, so extracting into
  # EXTRACT_DIR (e.g. /Applications) creates /Applications/Eclipse.app.
  rm -rf "${ECLIPSE_APP_DIR}"
  mkdir -p "${EXTRACT_DIR}"
  tar -xzf "${ARCHIVE_PATH}" -C "${EXTRACT_DIR}"

  if [[ ! -x "${ECLIPSE_BIN}" ]]; then
    echo "[installEclipse] ERROR: Eclipse binary not found at ${ECLIPSE_BIN} after extraction."
    echo "[installEclipse] Contents of ${EXTRACT_DIR}:"
    ls -la "${EXTRACT_DIR}" || true
    exit 1
  fi
  echo "[installEclipse] Eclipse extracted successfully."
else
  echo "[installEclipse] Skipping download — using existing Eclipse installation."
fi

# ── Helper: install IUs with error handling ──────────────────────────────────

install_ius() {
  local step_name="$1"; shift
  local repo="$1"; shift
  # Remaining arguments are installable unit IDs.

  echo "[installEclipse] Installing ${step_name}..."
  echo "[installEclipse]   Repository: ${repo}"

  local iu_args=()
  for iu in "$@"; do
    iu_args+=(-installIU "${iu}")
  done

  "${ECLIPSE_BIN}" \
    -nosplash \
    -application org.eclipse.equinox.p2.director \
    -repository "${repo}" \
    "${iu_args[@]}" \
    -destination "${ECLIPSE_HOME}" \
    -profileProperties org.eclipse.update.install.features=true \
  || { echo "[installEclipse] ERROR: ${step_name} installation failed."; exit 1; }

  echo "[installEclipse] ${step_name} installed successfully."
}

# ── Step 5: Install Acceleo ──────────────────────────────────────────────────

install_ius "Acceleo" "${RELEASES_REPO_URL},${ACCELEO_REPO_URL}" \
  org.eclipse.acceleo.feature.group \
  org.eclipse.acceleo.ui.interpreter.ocl.feature.group \
  org.eclipse.acceleo.ui.interpreter.completeocl.feature.group \
  org.eclipse.emf.sdk.feature.group \
  org.eclipse.uml2.sdk.feature.group \
  org.eclipse.ocl.all.sdk.feature.group \
  org.eclipse.acceleo.query.feature.group \
  org.eclipse.acceleo.query.source.feature.group \
  org.antlr.runtime

# ── Step 6: Install Sirius ───────────────────────────────────────────────────

install_ius "Sirius" "${RELEASES_REPO_URL},${SIRIUS_REPO_URL}" \
  org.eclipse.sirius.common.acceleo.aql \
  org.eclipse.sirius.ui.properties \
  org.eclipse.sirius.aql.feature.group \
  org.eclipse.sirius.runtime.aql.feature.group \
  org.eclipse.sirius.properties.feature.feature.group \
  org.eclipse.sirius.aql.source.feature.group \
  org.eclipse.sirius.interpreter.feature.feature.group \
  org.eclipse.sirius.interpreter.feature.source.feature.group \
  org.eclipse.sirius.model.feature.source.feature.group \
  org.eclipse.sirius.properties.feature.source.feature.group \
  org.eclipse.sirius.runtime.aql.source.feature.group \
  org.eclipse.sirius.runtime.ide.ui.feature.group \
  org.eclipse.sirius.specifier.feature.group \
  org.eclipse.sirius.specifier.ide.ui.aql.feature.group \
  org.eclipse.sirius.specifier.ide.ui.aql.source.feature.group \
  org.eclipse.sirius.specifier.ide.ui.feature.group \
  org.eclipse.sirius.specifier.ide.ui.source.feature.group \
  org.eclipse.sirius.specifier.properties.feature.feature.group \
  org.eclipse.sirius.specifier.properties.feature.source.feature.group \
  org.eclipse.sirius.specifier.source.feature.group \
  org.eclipse.eef.ext.widgets.reference.feature.feature.group \
  org.eclipse.eef.ext.widgets.reference.feature.source.feature.group \
  org.eclipse.eef.sdk.feature.feature.group \
  org.eclipse.eef.sdk.feature.source.feature.group

# ── Step 7: Install CDT ─────────────────────────────────────────────────────

install_ius "CDT" "${CDT_REPO_URL}" \
  org.eclipse.cdt.feature.group

echo "[installEclipse] Eclipse installation complete: ${ECLIPSE_APP_DIR}"
