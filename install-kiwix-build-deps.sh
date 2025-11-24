#!/usr/bin/env bash
# Install all dependencies needed to compile Kiwix from source on Ubuntu
set -euo pipefail

echo "=== Installing Kiwix Build Dependencies for Ubuntu ==="

# Update package lists
echo "Updating package lists..."
sudo apt-get update

# Basic development tools and utilities
echo "Installing basic development tools..."
sudo apt-get install -y \
  wget curl git jq unzip \
  build-essential cmake pkg-config \
  meson ninja-build

# Python build tools (meson/ninja via pip for latest versions)
echo "Installing Python build tools..."
if command -v pip3 &>/dev/null; then
  pip3 install --user meson ninja
elif command -v pip &>/dev/null; then
  pip install --user meson ninja
else
  echo "Warning: pip not found, skipping Python package installation"
fi

# Core libraries for libzim (ZIM file format)
echo "Installing libzim dependencies..."
sudo apt-get install -y \
  liblz4-dev \
  libzstd-dev \
  libxapian-dev \
  libicu-dev

# Libraries for kiwix-lib (Kiwix core functionality)
echo "Installing kiwix-lib dependencies..."
sudo apt-get install -y \
  libcurl4-openssl-dev \
  libmicrohttpd-dev \
  libevent-dev \
  libfmt-dev \
  libctpl-dev

echo ""
echo "=== Dependency Installation Complete ==="
echo ""
echo "You can now build Kiwix components in this order:"
echo "  1. libzim"
echo "  2. Mustache (header-only, just copy)"
echo "  3. docopt.cpp"
echo "  4. kiwix-lib"
echo "  5. kiwix-tools"
echo ""
echo "See KIWIX_BUILD_README.md for detailed build instructions."
