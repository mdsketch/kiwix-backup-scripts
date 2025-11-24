# Kiwix Monthly Backup Scripts

Automated backup system for Wikipedia ZIM files and Kiwix applications. Manages up to 1.8TB of monthly Wikipedia archives with automatic rotation.

## Features

- ✅ **Monthly Wikipedia ZIM Downloads** - Automatically fetches latest Wikipedia dumps
- ✅ **Smart Storage Management** - Keeps up to 1.8TB with automatic rotation of old backups
- ✅ **Kiwix Applications** - Downloads Windows, Linux, and server binaries
- ✅ **Source Code Mirroring** - Clones all necessary GitHub repositories
- ✅ **Offline Build Support** - Downloads Ubuntu .deb packages for offline compilation
- ✅ **SHA256 Verification** - Ensures download integrity
- ✅ **Cron Compatible** - Designed to run unattended via cron

## Files

- **`wikipediaDL.sh`** - Main backup script
- **`KIWIX_BUILD_README.md`** - Complete guide to compile Kiwix from source
- **`install-kiwix-build-deps.sh`** - One-command dependency installer for Ubuntu
- **`.gitignore`** - Excludes downloaded binaries and archives from version control

## Quick Start

### 1. Install Dependencies

```bash
sudo apt install -y wget curl git jq unzip
```

### 2. Configure Storage Paths

Edit `wikipediaDL.sh` and set your paths:
```bash
STORAGE_DIR="/wiki/kiwix/zim"     # Where ZIM files are stored (needs ~1.8TB)
REPOS_DIR="/wiki/kiwix/repos"     # Git repos
BIN_DIR="/wiki/kiwix/apps"        # Downloaded binaries
```

### 3. Run Manually (First Time)

```bash
chmod +x wikipediaDL.sh
sudo bash wikipediaDL.sh
```

### 4. Setup Cron for Monthly Execution

Run on the 1st of each month at 2 AM:

```bash
crontab -e
```

Add this line:
```cron
0 2 1 * * /bin/bash /path/to/wikipediaDL.sh >> /var/log/kiwix-cron.log 2>&1
```

## What Gets Downloaded

### Wikipedia Archives
- Latest English Wikipedia (full with images) - ~100GB per month
- Stored in `/wiki/kiwix/zim/`
- Automatic rotation keeps newest 18-19 months

### Kiwix Applications
- **Desktop**: Windows .exe, Linux AppImage, .deb packages
- **Server**: Linux x86_64 & ARM64 binaries, Windows x86_64 & i686
- **Kiwix JS**: Cross-platform HTML5 reader
- Stored in `/wiki/kiwix/apps/`

### Source Code Repositories
- kiwix-tools, kiwix-desktop, kiwix-js
- libzim, kiwix-lib
- docopt.cpp, Mustache
- Stored in `/wiki/kiwix/repos/`

### Build Dependencies (Ubuntu)
- .deb packages for Ubuntu 22.04 LTS (jammy)
- .deb packages for Ubuntu 24.04 LTS (noble)
- Stored in `/wiki/kiwix/apps/ubuntu-debs/`

## Compiling from Source

See **[KIWIX_BUILD_README.md](KIWIX_BUILD_README.md)** for complete build instructions.

Quick install dependencies:
```bash
chmod +x install-kiwix-build-deps.sh
sudo bash install-kiwix-build-deps.sh
```

## Storage Requirements

- **ZIM Files**: ~1.8TB (18-19 months of backups @ ~100GB/month)
- **Applications**: ~2-5GB
- **Source Repos**: ~500MB-1GB
- **Build Packages**: ~500MB-1GB
- **Total**: ~1.85TB recommended

## Configuration Options

Edit `wikipediaDL.sh` to customize:

```bash
MAX_BYTES=$((1800 * 1024 * 1024 * 1024))  # Storage cap (1.8TB)

ZIM_BASENAME="wikipedia_en_all_maxi"       # ZIM type to download
# Options: wikipedia_en_all_maxi (full with images)
#          wikipedia_en_all_nopic (no images)
#          wikipedia_en_mini (mini version)

UBUNTU_RELEASES=("jammy" "noble")          # Ubuntu versions for .deb packages
```

## Logs

- **Main log**: `/var/log/kiwix-backup.log`
- **Cron log**: `/var/log/kiwix-cron.log` (if configured)

View real-time:
```bash
tail -f /var/log/kiwix-backup.log
```

## Running the Kiwix Server

After download, serve Wikipedia offline:

```bash
# Using pre-compiled binary
/wiki/kiwix/apps/kiwix-tools_linux-x86_64-*/kiwix-serve --port=8080 /wiki/kiwix/zim/wikipedia_*.zim

# Or if compiled from source
kiwix-serve --port=8080 /wiki/kiwix/zim/wikipedia_*.zim
```

Access at: `http://localhost:8080`

## Offline Installation

To install build dependencies on an offline system:

```bash
# Copy ubuntu-debs directory to offline system
cd /wiki/kiwix/apps/ubuntu-debs/jammy/    # or noble/
sudo dpkg -i *.deb
sudo apt-get install -f  # Resolve any dependencies
```

## Troubleshooting

**Script fails with "unbound variable"**
- Make sure all configuration variables are set at the top of the script

**Download fails**
- Check internet connection
- Verify Wikimedia dumps are available: https://dumps.wikimedia.org/kiwix/zim/wikipedia/

**Storage full**
- Adjust `MAX_BYTES` in the script
- Manually delete old ZIM files from `STORAGE_DIR`

**Can't compile from source**
- Run `install-kiwix-build-deps.sh` first
- See detailed troubleshooting in `KIWIX_BUILD_README.md`

## License

These scripts are provided as-is for managing Kiwix backups. Kiwix and Wikipedia content have their own licenses.

## Resources

- Kiwix Website: https://www.kiwix.org/
- Kiwix Applications: https://kiwix.org/en/applications/
- Wikipedia Dumps: https://dumps.wikimedia.org/
- GitHub: https://github.com/kiwix/
