#!/bin/bash
# Full automated Zori OS ISO build with KDE Plasma + Calamares
set -e

# ---------------- Config ----------------
WORK_DIR=~/zori/work
OUT_DIR=~/zori/out
ZORI_DIR=~/zori/releng
USER_NAME="user"
ISO_NAME="zorios"

PACKAGES=(
    # Core system and desktop
    "linux" "linux-firmware" "base" "sudo" "nano" "vim"
    "plasma" "kde-applications" "konsole" "dolphin" "kate"
    "firefox" "sddm" "networkmanager"

    # Qt5 packages required for Calamares
    "qt5-base" "qt5-tools" "qt5-declarative" "qt5-svg" "qt5-x11extras" "qt5-quickcontrols2"

    # Build dependencies
    "boost" "extra-cmake-modules" "archiso" "git" "cmake" "base-devel"
)

# ---------------- Install dependencies ----------------
echo "[*] Installing all required packages..."
sudo pacman -S --needed "${PACKAGES[@]}"

# ---------------- Prepare working directory ----------------
echo "[*] Preparing Archiso working directory..."
mkdir -p ~/zori
cp -r /usr/share/archiso/configs/releng/ ~/zori
cd ~/zori

# ---------------- Build Calamares ----------------
echo "[*] Cloning and building Calamares..."
git clone --branch v3.3.9 https://github.com/calamares/calamares calamares-src
cd calamares-src
rm -rf build
mkdir build
cd build

# Explicitly point CMake to Qt5 on Arch
export CMAKE_PREFIX_PATH=/usr/lib/qt5
cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DENABLE_SUG=OFF

echo "[*] Compiling Calamares..."
make -j$(nproc)
sudo make install DESTDIR="$ZORI_DIR/airootfs"

cd "$ZORI_DIR"

# ---------------- Configure packages.x86_64 ----------------
echo "[*] Configuring packages.x86_64..."
PKG_FILE="$ZORI_DIR/packages.x86_64"
> "$PKG_FILE"
for pkg in "${PACKAGES[@]}"; do
    echo "$pkg" >> "$PKG_FILE"
done

# ---------------- Configure profiledef.sh ----------------
echo "[*] Writing custom profiledef.sh..."
PROFILE_FILE="$ZORI_DIR/profiledef.sh"
cat > "$PROFILE_FILE" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="zorios"
iso_label="zori_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="zori"
iso_application="zori os live"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
'uefi-ia32.systemd-boot.esp' 'uefi-x64.systemd-boot.esp'
'uefi-ia32.systemd-boot.eltorito' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
["/etc/shadow"]="0:0:400"
["/root"]="0:0:750"
["/root/.automated_script.sh"]="0:0:755"
["/root/.gnupg"]="0:0:700"
["/usr/local/bin/choose-mirror"]="0:0:755"
["/usr/local/bin/Installation_guide"]="0:0:755"
["/usr/local/bin/livecd-sound"]="0:0:755"
)
EOF
chmod +x "$PROFILE_FILE"

# ---------------- KDE Plasma auto-login ----------------
echo "[*] Setting up SDDM auto-login..."
AIROOTFS_CONF="$ZORI_DIR/airootfs/etc/sddm.conf"
mkdir -p "$(dirname "$AIROOTFS_CONF")"
cat > "$AIROOTFS_CONF" <<EOF
[Autologin]
User=$USER_NAME
Session=plasma.desktop
Relogin=false

[Theme]
Current=breeze
EOF

# Copy /etc/skel for default configs
mkdir -p "$ZORI_DIR/airootfs/etc/skel"
cp -r /etc/skel/* "$ZORI_DIR/airootfs/etc/skel/"

# Enable SDDM service
ln -sf /usr/lib/systemd/system/sddm.service "$ZORI_DIR/airootfs/etc/systemd/system/display-manager.service"

# ---------------- Minimal Calamares config ----------------
echo "[*] Configuring Calamares..."
CALAMARES_CONF_DIR="$ZORI_DIR/airootfs/etc/calamares"
mkdir -p "$CALAMARES_CONF_DIR"
cat > "$CALAMARES_CONF_DIR/settings.conf" <<EOF
[general]
installer_name = Zori KDE Installer
EOF

# ---------------- Build ISO ----------------
mkdir -p "$WORK_DIR" "$OUT_DIR"
echo "[*] Building ISO with mkarchiso..."
sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$ZORI_DIR"

echo "[*] ISO built successfully!"
echo "Output location: $OUT_DIR"
