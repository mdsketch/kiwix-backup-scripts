# Kiwix Build from Source - Ubuntu Instructions

This README documents how to compile Kiwix tools from source on Ubuntu.

## Prerequisites - Install Build Dependencies

```bash
# Basic development tools
sudo apt-get update
sudo apt-get install -y \
  wget curl git jq unzip \
  build-essential cmake pkg-config \
  meson ninja-build

# Python build tools
pip install meson ninja

# Core libraries for libzim
sudo apt-get install -y \
  liblz4-dev libzstd-dev \
  libxapian-dev libicu-dev

# Libraries for kiwix-lib
sudo apt-get install -y \
  libcurl4-openssl-dev \
  libmicrohttpd-dev \
  libevent-dev \
  libfmt-dev \
  libctpl-dev
```

## Build Order

The components must be built in this specific order due to dependencies:

### 1. Build libzim (ZIM file format library)

```bash
cd /wiki/kiwix/repos/libzim
git checkout 9.4.0    # or latest stable version
meson setup build
ninja -C build
sudo ninja -C build install
sudo ldconfig
```

### 2. Install Mustache (C++ templating library)

```bash
cd /wiki/kiwix/repos/Mustache
git checkout v4.1    # or latest stable version
sudo mkdir -p /usr/local/include
sudo cp mustache.hpp /usr/local/include/
```

### 3. Build docopt.cpp (command-line parser)

```bash
cd /wiki/kiwix/repos/docopt.cpp
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install
sudo ldconfig
```

### 4. Build kiwix-lib (Kiwix core library)

```bash
cd /wiki/kiwix/repos/kiwix-lib
git checkout 14.1.0    # or latest stable version
meson setup build
ninja -C build
sudo ninja -C build install
sudo ldconfig
```

### 5. Build kiwix-tools (CLI tools including kiwix-serve)

```bash
cd /wiki/kiwix/repos/kiwix-tools
meson setup build
ninja -C build
sudo ninja -C build install
sudo ldconfig
```

## Verify Installation

```bash
kiwix-serve --version
kiwix-manage --version
```

## Running Kiwix Server

To serve a ZIM file:

```bash
kiwix-serve --port=8080 /wiki/kiwix/zim/wikipedia_en_all_maxi_2025-08.zim
```

Then open a browser to: `http://localhost:8080`

## Troubleshooting

### Missing Dependencies Error

If you get "Run-time dependency X found: NO":
- Make sure you installed all prerequisites listed above
- Run `sudo ldconfig` after installing libraries
- Check that pkg-config can find the library: `pkg-config --modversion <library>`

### Build Directory Already Exists

If meson complains about existing build directory:
```bash
rm -rf build
meson setup build
```

### Library Not Found at Runtime

If you get library errors when running compiled binaries:
```bash
sudo ldconfig
# Verify library paths
ldconfig -p | grep kiwix
ldconfig -p | grep zim
```

## Updating to Latest Version

To rebuild with the latest code:

```bash
# Pull latest changes
cd /wiki/kiwix/repos/<repo-name>
git pull

# Clean and rebuild
rm -rf build
meson setup build
ninja -C build
sudo ninja -C build install
sudo ldconfig
```

Rebuild in the same order: libzim → Mustache → docopt.cpp → kiwix-lib → kiwix-tools

## Additional Resources

- Kiwix Build Documentation: https://github.com/kiwix/kiwix-tools#compilation
- libzim Documentation: https://github.com/openzim/libzim
- Kiwix Library: https://github.com/kiwix/kiwix-lib

## Notes

- Version numbers (9.4.0, 14.1.0, v4.1) are examples - check GitHub releases for latest stable versions
- The monthly backup script downloads source code to `/wiki/kiwix/repos/`
- Use `nproc` to utilize all CPU cores: `make -j$(nproc)`
- Always run `sudo ldconfig` after installing shared libraries
