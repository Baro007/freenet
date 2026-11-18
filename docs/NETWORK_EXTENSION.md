# Network Extension status (Faz 3)

## Goal

Replace `networksetup` + SOCKS + sudoers with a **Packet Tunnel Provider** (`NetworkExtension`) for system-wide, leak-resistant routing and kill-switch.

## Current status (this tree)

| Item | Status |
|------|--------|
| Intent engines (DPI / sing-box / WARP / Tor SOCKS) | Implemented (SOCKS path) |
| Packet Tunnel Provider target | **Not provisioned** in this environment |
| Apple Developer team + NE entitlements | **Unavailable / not configured** |
| Kill-switch via NE | Deferred |

## Why incomplete is allowed

Full NE requires:

1. Paid Apple Developer Program membership  
2. App ID + Network Extension entitlement  
3. Provisioning profiles for app + appex  
4. Notarization for distribution  

Without those credentials, shipping a fake “connected system VPN” would be dishonest. Freenet therefore keeps the **complete SOCKS MVP** (including Tor) and documents NE as the next infrastructure step.

## Scaffold

See `app/NetworkExtensionStub.swift` for the intended extension boundary and TODO hooks. No binary appex is built until signing is available.

## Follow-up checklist

- [ ] Create App ID with Packet Tunnel  
- [ ] Add `FreenetTunnel.appex` target  
- [ ] Move proxy/tunnel start into extension process  
- [ ] Kill-switch + DNS lock  
- [ ] Remove sudoers install path  
