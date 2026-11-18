# Freenet Roadmap

> macOS menubar uygulaması: ücretsiz, açık kaynak, sansür aşımı **veya** gerçek anonimlik — kullanıcı bilinçli seçer.  
> Android kapsam dışı.  
> Son güncelleme: 2026-07-11

---

## Ürün ilkesi

Freenet motor isimlerini satmaz; **niyet** satar. “Sınırsız hız” ile “anonimlik” aynı anda vaat edilmez.

| Niyet (UI) | Arka plan motor(lar) | Ne korur | Ne korumaz |
|------------|----------------------|----------|------------|
| **Hızlı** | DPI (`ciadpi`) ve/veya **sing-box** (birinci sınıf) | DPI/SNI engeli; max hız | IP gizliliği, anonimlik |
| **Dengeli** | WARP (WireGuard / Cloudflare) | IP maskeleme, IP ban, public Wi‑Fi | Cloudflare’e güven; gerçek anonimlik değil |
| **Maks. Gizlilik** | Tor + pluggable transport (obfs4 / snowflake / webtunnel) | Gerçek çok-sıçramalı anonimlik | Hız; bazı siteler (exit politikası) |

### Kilitleme kararları (2026-07-11)

| ID | Konu | Karar |
|----|------|--------|
| **A** | Anonimlik | **Tor merkezde.** Maks. Gizlilik = gerçek anonimlik. WARP “gizlilik” diye satılmaz. |
| **B** | NetworkExtension | **Tor (SOCKS) önce.** NE (Faz 3) sonra, sağlam temele oturtulur. |
| **C** | WARP | **Kalır** → niyet **Dengeli**. Cloudflare güven modeli UI + README’de açık yazılır. |
| **sing-box** | Motor rolü | **Birinci sınıf motor.** Yedek/gizli seçenek değil. Kullanıcı memnuniyeti yüksek; Hızlı niyetinin gelişmiş omurgası. |

### sing-box politikası

- **Hızlı** niyetinde varsayılan tercih (ayarlanabilir): `sing-box` (TLS record fragment + DoH) **veya** klasik `ciadpi`.
- Ayarlar → “Hızlı motor”: `Otomatik` · `sing-box` · `DPI (ciadpi)`.
- `Otomatik`: önce tercih edilen; bootstrap/bağlantı başarısızsa diğerine düş (self-heal ile uyumlu).
- Menüde ham “sing-box Modu” yerine niyet dili; gelişmiş panelde motor adı görünür (şeffaflık).
- Mevcut `sing-box` config (SOCKS 1081, `tls_record_fragment`, Cloudflare DoH) korunur ve sürümlenir; kırıcı değişiklik semver ile.

---

## Mevcut durum (özet)

| Alan | Durum |
|------|--------|
| Kod | ~1337 satır Swift; `AppController` monolit (~779 satır) |
| Motorlar | DPI, WARP, sing-box — hepsi sansür/IP; **Tor yok** |
| Tünel | `networksetup` SOCKS + sudoers (kırılgan) |
| Android | Repo’nun büyük kısmı — **silinecek** |
| Dağıtım | `curl \| bash`, ad-hoc sign, Homebrew runtime (WARP) |
| Güçlü yanlar | Hibrit fikir, menubar UX, self-heal, orphan proxy cleanup, native Swift |

**Kritik gerilim (belgelenmeli):**  
Anonimlik (Tor) her zaman yavaştır. Hız vaadi yalnızca **Hızlı** / **Dengeli** niyetlerindedir.

---

## Hedef mimari

```
Freenet.app (macOS 13+, SwiftUI, menubar)
│
├── Presentation
│   ├── MenuBarController
│   ├── ModePickerView          // Hızlı | Dengeli | Maks. Gizlilik
│   ├── DashboardView
│   ├── OnboardingView          // dürüst tehdit modeli
│   └── SettingsView            // Hızlı motor, bridge, kill-switch
│
├── State
│   ├── AppState
│   ├── IntentMode              // .fast | .balanced | .maxPrivacy
│   └── FastEnginePreference    // .auto | .singbox | .dpi
│
├── Engines
│   ├── protocol Engine
│   ├── EngineManager
│   ├── DPIEngine               // ciadpi
│   ├── SingBoxEngine           // ★ birinci sınıf
│   ├── WarpEngine
│   └── TorEngine               // ★ yeni (Faz 2)
│
├── Network
│   ├── ProxyService            // şimdilik networksetup
│   └── FreenetTunnel (NE)      // Faz 3
│
└── Security
    ├── Bundled binaries + SHA-256
    ├── Signing + notarization
    └── Allowlist input validation
```

---

## Fazlar

### Faz 0 — Temizlik ve ürün sözleşmesi

**Süre:** ~0.5–1 gün · **Risk:** düşük

- [ ] `android/` ve tüm Kotlin’i sil
- [ ] `app/build/` ve binary artifact’ları git’ten çıkar (gerekirse LFS/release’e taşı)
- [ ] README.md + README.tr.md → Mac-only; niyet tablosu; “anonimlik yalnız Maks. Gizlilik”
- [ ] Tagline: sansür aşımı **veya** anonimlik — bilinçli seçim
- [ ] `docs/THREAT_MODEL.md` iskeleti
- [ ] Bu `ROADMAP.md` repoda kalsın

**Çıkış:** Android yok; README dürüst; clone = yalnızca macOS.

---

### Faz 1 — Modüler refactor

**Süre:** ~3–5 gün · **Risk:** orta · **Bağımlılık:** Faz 0

- [ ] `AppController` böl: `EngineManager` + motorlar + `AppState` + saf SwiftUI menubar
- [ ] `Engine` protokolü; `DPIEngine`, `SingBoxEngine`, `WarpEngine` implementasyonları
- [ ] **sing-box** birinci sınıf: `FastEnginePreference` + Settings UI
- [ ] Self-heal ve orphan proxy cleanup `EngineManager`’a taşı (davranış korunur)
- [ ] AppleScript: kullanıcı string’i yok; allowlist komut şablonları
- [ ] `dpiArgs` doğrulama (allowlist bayraklar, port aralığı)
- [ ] Xcode veya SwiftPM yapı; `build.sh` CI’ya
- [ ] Regression: üç motor (DPI / sing-box / WARP) eski gibi çalışır

**Örnek protokol:**

```swift
protocol Engine: AnyObject {
    var id: String { get }
    var privacyLevel: PrivacyLevel { get } // none | ipMask | anonymity
    func start() async throws
    func stop() async
    var isRunning: Bool { get }
    var socksProxy: (host: String, port: Int)? { get }
}
```

**Çıkış:** Davranış aynı veya daha iyi; yeni motor = 1 dosya + kayıt; testler yeşil.

---

### Faz 2 — TorEngine (asıl anonimlik farkı) ★

**Süre:** ~1–2 hafta · **Risk:** orta-yüksek · **Bağımlılık:** Faz 1  
**Not:** Hâlâ SOCKS + `networksetup` (NE yok) — bilinçli.

- [ ] Bundle: `tor`, `obfs4proxy`, `snowflake-client` (+ checksum)
- [ ] `TorEngine`: localhost SOCKS, control port, bootstrap log
- [ ] Bridge desteği: built-in + kullanıcı `obfs4` / `webtunnel` / `snowflake`
- [ ] Intent **Maks. Gizlilik** → Tor; UI’da yavaşlık / site engeli uyarısı
- [ ] DNS Tor üzerinden; sızıntı notları belgelensin
- [ ] Hibrit (v1.1 hedefi): sansürlü ağda PT köprü + Tor = “hibrit”in en güçlü hali
- [ ] check.torproject.org ile doğrulama adımı (Dashboard ipucu)

**Çıkış:** Maks. Gizlilik = “Congratulations, this browser is configured to use Tor.”  
**MVP-Anonim** bu fazın sonunda: Android’siz, modüler, Tor’lu menubar.

---

### Faz 3 — NetworkExtension (sistem tüneli)

**Süre:** ~2–4 hafta · **Risk:** yüksek · **Bağımlılık:** Faz 1 (+ idealde Faz 2 çalışıyor)

- [ ] Packet Tunnel Provider hedefi; sudoers/`networksetup` hilelerini kaldır
- [ ] NE önce “yakalayıcı”: mevcut process motorları (sing-box, ciadpi, tor) arkada
- [ ] Kill-switch: tünel kopunca dışarı trafik yok
- [ ] DNS kilidi; IPv6 sızıntı seçeneği
- [ ] WARP: mümkünse Homebrew `wg-quick` bağımlılığını kes / NE path
- [ ] Sızıntı test paketi: DNS, IPv6, UDP, WebRTC (dokümantasyon)

**Çıkış:** Parola/sudoers şart değil; sistem geneli; kill-switch çalışır.

---

### Faz 4 — Güven ve tedarik zinciri

**Süre:** Faz 2–3 ile paralel, ~1 hafta odak

- [ ] Tüm ikililer: imza + SHA-256; start öncesi verify
- [ ] `curl | bash` kaldır veya yalnızca checksum doğrulayan imzalı yol
- [ ] Developer ID + notarization (.dmg)
- [ ] AppleScript enjeksiyon path’leri kapalı (veya NE ile silinmiş)
- [ ] Reproducible / pin’li build notları (`docs/BUILD.md`)
- [ ] Tor (GPL) dağıtım uyumu belgelensin; app MIT kalabilir

**Çıkış:** Gatekeeper dostu DMG; kullanıcı checksum doğrulayabilir.

---

### Faz 5 — UX / şık cilası

**Süre:** ~1 hafta · **Bağımlılık:** Faz 1–2 API

- [ ] Menubar: durum + niyet chip + tek toggle
- [ ] Onboarding (3 ekran): neyi gizler / neyi gizlemez
- [ ] Dashboard: gerçek IP · görünen IP · DNS · aktif niyet · motor (sing-box/dpi/warp/tor) · log
- [ ] Intent renkleri: Hızlı=turuncu · Dengeli=mavi · Gizlilik=mor
- [ ] Hızlı ayarı: sing-box / DPI / Otomatik (birinci sınıf UX)
- [ ] Bağlıyken mod değişimi: kilit veya “yeniden bağlan” onayı

**Çıkış:** İlk 10 sn’de niyet anlaşılır; yanlış “tam anonim” vaadi yok.

---

### Faz 6 — Şeffaflık

**Süre:** sürekli

- [ ] `docs/THREAT_MODEL.md` dolu matris (niyet × tehdit)
- [ ] `docs/PRIVACY.md` — telemetri yok beyanı
- [ ] Release checklist: checksum, binary kaynak URL’leri
- [ ] Issue şablonları (intent, macOS, log)
- [ ] İsteğe bağlı bağımsız inceleme çağrısı

---

## Zaman çizelgesi (hedef)

```
Hafta 1       Faz 0 + Faz 1 iskelet
Hafta 2       Faz 1 tamam + regression (DPI / sing-box / WARP)
Hafta 3–4     Faz 2 Tor + Maks. Gizlilik UI
Hafta 5       Faz 5 onboarding / dashboard (Tor ile anlamlı)
Hafta 6–9     Faz 3 NetworkExtension
Paralel       Faz 4 signing / checksums
Sonrası       Faz 6 + v1.0 release
```

| Kilometre taşı | Tanım |
|----------------|--------|
| **MVP-Anonim** | Faz 0+1+2 — Tor’lu, dürüst niyet UI, SOCKS tünel |
| **v1.0 Mükemmel** | + Faz 3+4+5 — NE, imza, sızıntı kontrolü, şık UX |

---

## Bilinçli yapılmayacaklar (v1)

| Yapma | Neden |
|-------|--------|
| Android | Odak Mac |
| “Hızlı + tam anonim” tek buton | Teknik yalan |
| Xray REALITY / topluluk sunucusu | Operasyon + güven; v2 |
| Auto-pilot site→motor v1 | Yanlış güvenlik hissi |
| PowerTunnel / Node / Java motorları | Native hafiflik |
| App Store zorunluluğu v1 | Önce notarized DMG |

---

## Başarı metrikleri (v1.0)

1. **Dürüstlük** — Her niyetin sınırı UI = README = threat model  
2. **Anonimlik** — Maks. Gizlilik Tor check + (NE sonrası) sızıntı testleri  
3. **Hız** — Hızlı (özellikle **sing-box** tercihinde) ISP hızına yakın  
4. **Basitlik** — Tek tık AÇ; sürekli parola yok  
5. **Güven** — Notarized DMG + checksum; `curl|bash` yok  
6. **Genişletilebilirlik** — Yeni motor ≤ 1 dosya + `EngineManager` kaydı  
7. **sing-box** — Kullanıcı tercihi korunur; regression yok  

---

## Threat model iskeleti (Faz 0/6)

| Tehdit | Hızlı (DPI/sing-box) | Dengeli (WARP) | Maks. Gizlilik (Tor) |
|--------|----------------------|----------------|----------------------|
| ISP DPI / SNI engeli | Evet | Evet | PT ile evet |
| IP ban | Hayır | Evet | Evet (exit IP) |
| ISS trafiği okusun | Hedef şifreliyse içerik hayır; meta veri evet | Cloudflare görür | Giriş köprüsü / guard sınırlı |
| Hedef site gerçek IP | **Görür** | Cloudflare IP görür | Exit görür; senin IP’n değil |
| Cloudflare / tek şirket | — | **Güven modeli** | Yok |
| Hız | En yüksek | Yüksek | Düşük |

---

## Sıradaki adım

1. Faz 0 PR: android sil, README sadeleştir, threat model iskeleti  
2. Faz 1 PR: `Engine` + `SingBoxEngine` birinci sınıf + `AppState`  
3. Faz 2: Tor  

Uygulama sırası: **0 → 1 → 2 → (5 ile 2 örtüşebilir) → 3 → 4 tamamla → 6**.

---

## Değişiklik günlüğü (kararlar)

| Tarih | Not |
|-------|-----|
| 2026-07-11 | A/B/C varsayılan kabul. sing-box birinci sınıf motor (Hızlı niyeti omurgası). ROADMAP oluşturuldu. |
