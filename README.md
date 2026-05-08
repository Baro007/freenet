# 🛡️ Freenet (macOS)

![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-apple?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Status](https://img.shields.io/badge/Status-Active-success?style=flat-square)

**Bypass censorship. No account. No subscription. Just click.**

The ultimate, zero-configuration hybrid internet censorship bypass tool for macOS. Inspired by the legendary GoodbyeDPI, but custom-built for Mac as a lightweight, native menubar application.

🇹🇷 [Türkçe dokümantasyon için tıklayın (Turkish README)](README.tr.md)

---

## ✨ Features

Freenet offers two distinct engines (modes) to counter different censorship tactics:

### 1. 🚀 DPI Mode (Local Bypass - ciadpi)
* **How it works:** Spawns a local SOCKS5 proxy (`127.0.0.1:1080`) that fragments your packets, circumventing SNI (Server Name Indication) filters applied by your ISP.
* **The Advantage:** Traffic is NOT routed through an external VPN. You get **zero speed loss**. Access blocked sites (like YouTube, X) at your maximum native internet speed.
* **Note:** This bypasses DPI but does not anonymize your IP.

### 2. 🌍 Tunnel Mode (WARP - wg-quick)
* **How it works:** If a site is blocked via strict IP-ban (not just DPI), the DPI mode won't suffice. Select "Tunnel Mode" to instantly route your traffic through a free, automated Cloudflare WARP WireGuard tunnel.
* **The Advantage:** Masks your real IP and securely bypasses absolute IP blocks. Zero configuration required—Freenet handles the keys and profiles for you.

### ⚡️ Passwordless 1-Click Toggle (Sudoers IPC)
VPN and DPI operations on macOS require root privileges. Freenet elegantly asks for your permission just *once* during initial setup to create a secure, restricted `/etc/sudoers.d/freenet` file. Afterwards, toggling modes is instant and requires **zero passwords**.

### 📊 Live Matrix Dashboard & Custom Settings
See what's happening under the hood! Freenet includes a real-time, matrix-style live log viewer for the DPI engine, and a Settings window to tweak DPI fragmentation arguments for different ISPs.

---

## 📦 One-Command Install

To install Freenet, simply open your Terminal (`Applications > Utilities > Terminal`) and paste this single command:

```bash
curl -fsSL https://raw.githubusercontent.com/Baro007/freenet/main/install.sh | bash
```

*This will automatically clone, build, and install the app to your `/Applications` folder.*

### Manual Install
If you prefer to build it manually:
```bash
git clone https://github.com/Baro007/freenet.git
cd freenet/app
./build.sh
cp -R build/freenet.app /Applications/
xattr -dr com.apple.quarantine /Applications/freenet.app
open /Applications/freenet.app
```

---

## 🛠️ First Usage

1. Click the shield 🛡️ icon in your macOS menubar.
2. Click **"Şifresiz Geçişi Aktif Et ⚡️"** (Enable Passwordless Toggle).
3. Enter your Mac password (one-time setup).
4. Click **ON / OFF** to enjoy an open internet!
5. Switch between `DPI` (for speed) and `WARP` (for IP blocks) from the **Connection Mode** menu.

---

## 🤝 Credits & Acknowledgements

Freenet stands on the shoulders of giants in the open internet community:
- [ciadpi (ByeDPI)](https://github.com/hufrea/byedpi) - The core DPI bypass engine.
- [WireGuard](https://www.wireguard.com/) & [Cloudflare WARP](https://1.1.1.1/) - The tunnel infrastructure.
- [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) & [SplitWire-Turkey](https://github.com/a-mertdincer/SplitWire-Turkey-macOS) - Community inspirations.

## 📝 License
MIT License. See [LICENSE](LICENSE) for details.
