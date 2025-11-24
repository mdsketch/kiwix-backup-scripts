#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# CONFIGURATION
# =====================================================================

STORAGE_DIR="/wiki/kiwix/zim"            # Where ZIM files are stored
REPOS_DIR="/wiki/kiwix/repos"            # Git repos for Kiwix projects
BIN_DIR="/wiki/kiwix/apps"               # Downloaded release binaries
LOGFILE="/var/log/kiwix-backup.log"

MAX_BYTES=$((1800 * 1024 * 1024 * 1024))    # 1.8 TiB rotation cap

# Choose the ZIM type you want to archive monthly
# Ex: wikipedia_en_all_maxi
#     wikipedia_en_all_nopic
#     wikipedia_en_mini
ZIM_BASENAME="wikipedia_en_all_maxi"

# GitHub repos to mirror
GITHUB_REPOS=(
  "kiwix/kiwix-desktop"
  "kiwix/kiwix-tools"
  "kiwix/kiwix-js"
  "openzim/libzim"
  "kiwix/kiwix-lib"
  "docopt/docopt.cpp"
  "kainjow/Mustache"
)

# Kiwix tools base URL for server binaries
KIWIX_TOOLS_BASE="https://download.kiwix.org/release/kiwix-tools"

# Wikimedia dump directories (primary + secondary)
DUMPS_PRIMARY="https://dumps.wikimedia.org/kiwix/zim/wikipedia/"
DUMPS_FALLBACK="https://dumps.wikimedia.org/other/kiwix/zim/wikipedia/"

# =====================================================================
# Check dependencies
# =====================================================================
for cmd in curl git sha256sum jq awk; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '$cmd' not found. Please install it first."
    exit 1
  fi
done

# Ensure PATH is set (important for cron)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

mkdir -p "$STORAGE_DIR" "$REPOS_DIR" "$BIN_DIR" "$(dirname "$LOGFILE")"

log() {
  echo "$(date --iso-8601=seconds) $*" | tee -a "$LOGFILE"
}

log "=== START KIWIX MONTHLY BACKUP ==="

# =====================================================================
# FUNCTION: Find newest ZIM file in one dump directory
# =====================================================================
find_newest_zim_url() {
  local base_url="$1" basename="$2"
  local html
  html=$(curl -fsSL "$base_url" || return 1)

  # Match: basename_YYYY-MM.zim
  local newest
  newest=$(printf '%s\n' "$html" \
    | grep -oE "${basename}_[0-9]{4}-[0-9]{2}\.zim" \
    | sort -u \
    | sort -t'_' -k2 -r \
    | head -n1)

  if [ -z "$newest" ]; then
    echo ""
    return 0
  fi

  echo "${base_url}${newest}"
}

# =====================================================================
# FUNCTION: Download newest ZIM from Wikimedia dumps
# =====================================================================
download_latest_from_dumps() {
  local basename="$1"
  log "Searching for newest ZIM for '${basename}'..."

  local url source_used

  url=$(find_newest_zim_url "$DUMPS_PRIMARY" "$basename")
  source_used="primary"

  if [ -z "$url" ]; then
    log "Primary contains no match, checking fallback..."
    url=$(find_newest_zim_url "$DUMPS_FALLBACK" "$basename")
    source_used="fallback"
  fi

  if [ -z "$url" ]; then
    log "ERROR: No ZIMs matching ${basename} found on Wikimedia dumps."
    return 2
  fi

  log "Selected ZIM (${source_used}): $url"

  local fname outpath tmp shaurl
  fname=$(basename "$url")
  outpath="${STORAGE_DIR}/${fname}"
  tmp="${outpath}.part"
  shaurl="${url}.sha256"

  # Already downloaded?
  if [ -f "$outpath" ]; then
    log "Already have ${fname}, skipping."
    echo "$outpath"
    return 0
  fi

  # Download ZIM
  log "Downloading ${fname}..."
  if ! curl -fSL --remote-time -o "$tmp" "$url"; then
    log "ERROR: Failed to download $url"
    rm -f "$tmp"
    return 3
  fi

  # Try SHA256 verification
  if curl -fsSL -o "${tmp}.sha256" "$shaurl"; then
    log "Downloaded SHA256 — verifying..."

    local hash
    hash=$(awk '{print $1}' "${tmp}.sha256" | head -n1)

    if echo "$hash" | grep -qE '^[0-9a-fA-F]{64}$'; then
      echo "${hash}  ${tmp}" > "${tmp}.sha256.norm"
      if ! sha256sum -c "${tmp}.sha256.norm"; then
        log "ERROR: SHA256 mismatch for $fname"
        rm -f "$tmp" "${tmp}.sha256" "${tmp}.sha256.norm"
        return 4
      fi
      log "SHA256 OK"
    else
      log "SHA256 file format unexpected — stored but not verified"
    fi
  else
    log "No .sha256 available; skipping verification."
  fi

  mv -f "$tmp" "$outpath"
  log "Saved ZIM → $outpath"
  echo "$outpath"
  return 0
}

# =====================================================================
# 1) Pre-download rotation check: ensure space for new ZIM
# =====================================================================
log "Pre-download storage check…"

total_bytes() {
  find "$STORAGE_DIR" -maxdepth 1 -type f -name '*.zim' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

AVG_ZIM_SIZE=$((100 * 1024 * 1024 * 1024))  # Assume ~100GB for new ZIM
current_bytes=$(total_bytes)
log "Current storage: $current_bytes bytes (max $MAX_BYTES)"

# Pre-emptively prune if we're close to the limit
if [ $((current_bytes + AVG_ZIM_SIZE)) -gt "$MAX_BYTES" ]; then
  log "Pre-pruning to make space for new download…"
  while [ $((current_bytes + AVG_ZIM_SIZE)) -gt "$MAX_BYTES" ]; do
    oldest=$(find "$STORAGE_DIR" -type f -name '*.zim' -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
    if [ -z "$oldest" ]; then
      log "No more ZIMs to delete"
      break
    fi
    log "Deleting oldest: $oldest"
    rm -f "$oldest"
    current_bytes=$(total_bytes)
    log "Now: $current_bytes bytes"
  done
fi

# =====================================================================
# 2) Fetch latest Wikimedia ZIM
# =====================================================================
LATEST_ZIM_PATH=$(download_latest_from_dumps "$ZIM_BASENAME") || {
  log "Failed to acquire new ZIM. Exiting."
  exit 1
}

log "Newest ZIM local path: $LATEST_ZIM_PATH"

# =====================================================================
# 3) Post-download rotation: Keep total ≤ 1.9 TiB
# =====================================================================
log "Post-download storage check…"

current_bytes=$(total_bytes)
log "Current: $current_bytes bytes (max $MAX_BYTES)"

if [ "$current_bytes" -gt "$MAX_BYTES" ]; then
  log "Post-pruning oldest ZIMs…"
  while [ "$current_bytes" -gt "$MAX_BYTES" ]; do
    oldest=$(find "$STORAGE_DIR" -type f -name '*.zim' -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
    if [ -z "$oldest" ]; then
      log "No more ZIMs to delete"
      break
    fi
    log "Deleting oldest: $oldest"
    rm -f "$oldest"
    current_bytes=$(total_bytes)
    log "Now: $current_bytes bytes"
  done
else
  log "No pruning required."
fi

# =====================================================================
# 4) Clone / update GitHub repositories
# =====================================================================
log "Updating Git repos…"
mkdir -p "$REPOS_DIR"
cd "$REPOS_DIR"

for repo in "${GITHUB_REPOS[@]}"; do
  name=$(basename "$repo")
  if [ -d "$name/.git" ]; then
    log "Updating $name"
    git -C "$name" fetch --all --prune 2>&1 | tee -a "$LOGFILE"
    git -C "$name" pull --ff-only 2>&1 | tee -a "$LOGFILE" || git -C "$name" pull 2>&1 | tee -a "$LOGFILE"
  else
    log "Cloning $repo"
    git clone "https://github.com/${repo}.git" "$name" 2>&1 | tee -a "$LOGFILE"
  fi
done

# =====================================================================
# 5) Download Kiwix applications (Windows, Linux, Server)
# =====================================================================
log "Fetching Kiwix tools and app binaries…"
mkdir -p "$BIN_DIR"
cd "$BIN_DIR"

# Helper: download latest GitHub release assets matching pattern
download_latest_asset() {
  local repo="$1" pattern="$2" description="$3"
  log "Querying GitHub releases for $repo ($description)"
  local api="https://api.github.com/repos/$repo/releases/latest"
  
  local release_data
  release_data=$(curl -fsSL "$api" 2>/dev/null) || {
    log "ERROR: Failed to fetch release info for $repo"
    return 1
  }

  echo "$release_data" | jq -r '.assets[] | "\(.name) \(.browser_download_url)"' \
    | while read -r name url; do
        if echo "$name" | grep -Eiq "$pattern"; then
          if [ ! -f "$name" ]; then
            log "Downloading asset: $name"
            if curl -fSL -o "$name" "$url"; then
              log "✓ Downloaded: $name"
            else
              log "ERROR: Failed to download $name"
              rm -f "$name"
            fi
          else
            log "Already have: $name"
          fi
        fi
      done
}

# Download kiwix-tools (Linux x86_64 - includes kiwix-serve, kiwix-manage, etc.)
log "Downloading kiwix-tools (server binaries for Linux x86_64)…"
KIWIX_TOOLS_LATEST=$(curl -fsSL "${KIWIX_TOOLS_BASE}/" | grep -oE 'kiwix-tools_linux-x86_64-[0-9.]+\.tar\.gz' | sort -V | tail -1)
if [ -n "$KIWIX_TOOLS_LATEST" ] && [ ! -f "$KIWIX_TOOLS_LATEST" ]; then
  log "Downloading $KIWIX_TOOLS_LATEST"
  curl -fSL -o "$KIWIX_TOOLS_LATEST" "${KIWIX_TOOLS_BASE}/${KIWIX_TOOLS_LATEST}" || log "ERROR: Failed to download kiwix-tools"
fi

# Download kiwix-tools (Linux ARM64/aarch64)
log "Downloading kiwix-tools (server binaries for Linux ARM64)…"
KIWIX_TOOLS_ARM=$(curl -fsSL "${KIWIX_TOOLS_BASE}/" | grep -oE 'kiwix-tools_linux-aarch64-[0-9.]+\.tar\.gz' | sort -V | tail -1)
if [ -n "$KIWIX_TOOLS_ARM" ] && [ ! -f "$KIWIX_TOOLS_ARM" ]; then
  log "Downloading $KIWIX_TOOLS_ARM"
  curl -fSL -o "$KIWIX_TOOLS_ARM" "${KIWIX_TOOLS_BASE}/${KIWIX_TOOLS_ARM}" || log "ERROR: Failed to download kiwix-tools ARM64"
fi

# Download kiwix-tools (Windows x86_64 - includes kiwix-serve.exe, kiwix-manage.exe, etc.)
KIWIX_TOOLS_WIN=$(curl -fsSL "${KIWIX_TOOLS_BASE}/" | grep -oE 'kiwix-tools_win-x86_64-[0-9.]+\.zip' | sort -V | tail -1)
if [ -n "$KIWIX_TOOLS_WIN" ] && [ ! -f "$KIWIX_TOOLS_WIN" ]; then
  log "Downloading $KIWIX_TOOLS_WIN"
  curl -fSL -o "$KIWIX_TOOLS_WIN" "${KIWIX_TOOLS_BASE}/${KIWIX_TOOLS_WIN}" || log "ERROR: Failed to download Windows kiwix-tools"
fi

# Download kiwix-tools (Windows i686/32-bit)
KIWIX_TOOLS_WIN32=$(curl -fsSL "${KIWIX_TOOLS_BASE}/" | grep -oE 'kiwix-tools_win-i686-[0-9.]+\.zip' | sort -V | tail -1)
if [ -n "$KIWIX_TOOLS_WIN32" ] && [ ! -f "$KIWIX_TOOLS_WIN32" ]; then
  log "Downloading $KIWIX_TOOLS_WIN32"
  curl -fSL -o "$KIWIX_TOOLS_WIN32" "${KIWIX_TOOLS_BASE}/${KIWIX_TOOLS_WIN32}" || log "ERROR: Failed to download Windows kiwix-tools i686"
fi

# Download kiwix-desktop (Windows .exe, Linux AppImage, and .deb)
download_latest_asset "kiwix/kiwix-desktop" "\.(exe|AppImage|deb)$" "Desktop app for Windows and Linux"

# Download kiwix-js (Windows, Linux, and platform-independent versions)
download_latest_asset "kiwix/kiwix-js-windows" "\.(exe|appx|msix|zip)$" "Kiwix JS for Windows"
download_latest_asset "kiwix/kiwix-js" "\.(AppImage|zip|tar\.gz)$" "Kiwix JS cross-platform"

# Download kiwix-android APK (bonus - works on some systems)
download_latest_asset "kiwix/kiwix-android" "\.apk$" "Android APK"

log "Saving copy of Kiwix applications page…"
curl -fsSL "https://kiwix.org/en/applications/" -o "kiwix-applications-page.html" 2>&1 | tee -a "$LOGFILE" || log "Warning: Failed to save applications page"

# =====================================================================
# 6) Download build dependency .deb packages (x86_64 only)
# =====================================================================
log "Downloading build dependency packages (Ubuntu x86_64)…"

DEBS_DIR="${BIN_DIR}/ubuntu-debs"
mkdir -p "$DEBS_DIR"
cd "$DEBS_DIR"

# List of build dependencies for compiling Kiwix from source
BUILD_DEPS=(
  "build-essential"
  "cmake"
  "pkg-config"
  "meson"
  "ninja-build"
  "liblz4-dev"
  "libzstd-dev"
  "libxapian-dev"
  "libicu-dev"
  "libcurl4-openssl-dev"
  "libmicrohttpd-dev"
  "libevent-dev"
  "libfmt-dev"
  "libctpl-dev"
  "git"
  "wget"
  "curl"
)

# Ubuntu releases to download packages for
UBUNTU_RELEASES=("jammy" "noble")  # Ubuntu 22.04 LTS and 24.04 LTS
ARCH="amd64"

download_deb_package() {
  local package="$1"
  local release="$2"
  local arch="$3"
  local release_dir="$4"
  
  log "Fetching package info for: $package (${release})"
  
  # Try main Ubuntu archive first
  local base_url="http://archive.ubuntu.com/ubuntu/pool"
  local search_url="https://packages.ubuntu.com/${release}/${arch}/${package}/download"
  
  # Get package download URL
  local deb_url
  deb_url=$(curl -fsSL "$search_url" 2>/dev/null | grep -oE "http://[^\"']+\.deb" | head -1)
  
  if [ -z "$deb_url" ]; then
    log "Warning: Could not find download URL for $package (${release})"
    return 1
  fi
  
  local deb_file
  deb_file=$(basename "$deb_url")
  
  # Save to release-specific directory
  if [ -f "${release_dir}/${deb_file}" ]; then
    log "Already have: $deb_file"
    return 0
  fi
  
  log "Downloading: $deb_file"
  if curl -fSL -o "${release_dir}/${deb_file}" "$deb_url"; then
    log "✓ Downloaded: $deb_file"
  else
    log "ERROR: Failed to download $deb_file"
    rm -f "${release_dir}/${deb_file}"
    return 1
  fi
}

# Download packages for each Ubuntu release
for release in "${UBUNTU_RELEASES[@]}"; do
  log "Processing packages for Ubuntu ${release}..."
  release_dir="${DEBS_DIR}/${release}"
  mkdir -p "$release_dir"
  
  for pkg in "${BUILD_DEPS[@]}"; do
    download_deb_package "$pkg" "$release" "$ARCH" "$release_dir" || true
  done
done

log "Build dependency packages saved to: $DEBS_DIR"
log "Ubuntu 22.04 packages: ${DEBS_DIR}/jammy/"
log "Ubuntu 24.04 packages: ${DEBS_DIR}/noble/"
log "To install offline: cd ${DEBS_DIR}/<release>/ && sudo dpkg -i *.deb; sudo apt-get install -f"

log "=== END KIWIX MONTHLY BACKUP ==="
