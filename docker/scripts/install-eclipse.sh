#!/bin/bash
# Install Eclipse Modeling Tools and required plugins
# This script uses the versions from versions.properties but installs a heavily optimized
# subset of plugins required for headless generation (to avoid bloating the Docker image).

set -euo pipefail

export MDE4CPP_HOME="/home/mde4cpp"
export MDE4CPP_ECLIPSE_TARGET_DIR="/home/eclipse/ide"

# Read versions from versions.properties
set -a
source "${MDE4CPP_HOME}/versions.properties"
set +a

ECLIPSE_DIR="${MDE4CPP_HOME}/eclipse"
ECLIPSE_BIN="${ECLIPSE_DIR}/eclipse"

if [ ! -f "${ECLIPSE_BIN}" ]; then
    echo 'Installing Eclipse Modeling Tools...'
    mkdir -p "${ECLIPSE_DIR}"
    cd /tmp
    
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        ECLIPSE_ARCH="aarch64"
    else
        ECLIPSE_ARCH="x86_64"
    fi
    
    # Construct URL dynamically based on versions.properties
    ECLIPSE_URL="https://ftp.halifax.rwth-aachen.de/eclipse/technology/epp/downloads/release/${MDE4CPP_ECLIPSE_VERSION//[[:space:]]/}/${MDE4CPP_ECLIPSE_MILESTONE//[[:space:]]/}/eclipse-modeling-${MDE4CPP_ECLIPSE_VERSION//[[:space:]]/}-${MDE4CPP_ECLIPSE_MILESTONE//[[:space:]]/}-linux-gtk-${ECLIPSE_ARCH}.tar.gz"
    
    echo "Downloading Eclipse from ${ECLIPSE_URL}..."
    wget -q --show-progress -O eclipse.tar.gz "${ECLIPSE_URL}"
    
    tar -xzf eclipse.tar.gz -C "${ECLIPSE_DIR}" --strip-components=1
    rm -f eclipse.tar.gz
    chmod +x "${ECLIPSE_BIN}"
    
    echo 'Installing headless Eclipse plugins (optimized subset for Docker)...'
    "${ECLIPSE_BIN}" -nosplash -application org.eclipse.equinox.p2.director         -repository "https://download.eclipse.org/releases/${MDE4CPP_ECLIPSE_VERSION//[[:space:]]/}"         -installIU org.eclipse.acceleo.feature.group         -installIU org.eclipse.emf.sdk.feature.group         -installIU org.eclipse.uml2.sdk.feature.group         -installIU org.eclipse.ocl.all.sdk.feature.group         -destination "${ECLIPSE_DIR}"         -profileProperties org.eclipse.update.install.features=true         -bundlepool "${ECLIPSE_DIR}"         -p2.os linux -p2.ws gtk -p2.arch ${ECLIPSE_ARCH}
    
    echo '✓ Eclipse installed'
else
    echo '✓ Eclipse already installed'
fi
