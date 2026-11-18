# Freenet Mimarisi İçin Rakip & Alternatif Backend İncelemesi

Freenet şu an iki temel sütun üzerine kurulu: **ciadpi (DPI bypass)** ve **WireGuard/WARP (Tünel)**. Ancak sansür teknolojileri (GFW, gelişmiş DPI donanımları vb.) sürekli gelişiyor. Freenet'i ileride çok daha güçlü ve "kırılmaz" bir yapıya kavuşturmak için GitHub'daki en güncel ve güçlü backend projelerini detaylıca inceledim.

İşte Freenet'in (Faz 4 ve ötesi için) mantığını veya direkt binary'sini kullanabileceği açık kaynak efsaneleri:

---

## 1. Gelişmiş DPI Bypass Motorları (ciadpi Alternatifleri)

Şu an kullandığımız `ciadpi` (ByeDPI) çok hafif ve harika. Ancak Türkiye'deki veya dünyadaki bazı ISP'ler (İnternet Servis Sağlayıcıları) SNI (Server Name Indication) paketlerini analiz etmekte çok daha agresifleşirse, şu projelere geçiş yapılabilir:

### 🟢 SpoofDPI (Go tabanlı)
*   **Repo:** `xvzc/SpoofDPI`
*   **Mantık:** ByeDPI ile aynı amaca hizmet eder ancak **Go** diliyle yazılmıştır. HTTP/HTTPS isteklerini parçalar. Go ile yazıldığı için macOS'ta derlenmesi ve dağıtılması (cross-compile) C diline göre çok daha modern ve yönetilebilirdir.
*   **Freenet'e Katkısı:** Eğer ileride `ciadpi`'ın C kodunu yönetmek veya Apple Silicon için optimize etmek zorlaşırsa, SpoofDPI'ın Go binary'sini `Resources` klasörüne gömerek aynı işi daha modern bir dille yapabiliriz.

### 🟢 PowerTunnel (Java tabanlı) / Green Tunnel (Node.js)
*   **Repo:** `krlvm/PowerTunnel` & `SadeghHayeri/GreenTunnel`
*   **Mantık:** Java ve Node.js ile yazılmış, HTTP/HTTPS paketlerini manipüle eden devasa projeler. 
*   **Değerlendirme:** Freenet'in "Hafif ve Native" (Simplicity First) felsefesine çok tersler. Bunları çalıştırmak için kullanıcının Mac'ine Java JRE veya Node.js kurmamız gerekir. **Kesinlikle uzak durulmalı.**

### 🟢 Zapret / nfqws (C/Linux Odaklı)
*   **Repo:** `bol-van/zapret`
*   **Mantık:** Sadece paketleri parçalamakla kalmaz, TCP katmanında eBPF ve nfqueue kullanarak çok daha derinlemesine (kernel seviyesinde) manipülasyon yapar.
*   **Değerlendirme:** Linux'ta efsanevi olmasına rağmen macOS'un çekirdeği (Darwin) bu Linux-spesifik ağ katmanı özelliklerini (netfilter) desteklemez. Doğrudan kullanılamaz.

---

## 2. "Heavy-Duty" (Ağır Zırhlı) Proxy Platformları

Eğer WARP tüneli komple bloklanırsa (ki bazı ülkelerde WireGuard protokolünün handshake paketleri anında tespit edilip engelleniyor), Freenet'in "Ağır Zırhlı" modlara ihtiyacı olacak. İşte dünyadaki en son teknoloji proxy platformları:

### 🚀 sing-box (Evrensel Proxy Platformu)
*   **Repo:** `SagerNet/sing-box`
*   **Mantık:** Şu an GitHub'daki **en popüler ve en modern** ağ yönlendirme aracıdır. Go ile yazılmıştır. Shadowsocks, Trojan, VLESS, Hysteria, TUIC dahil aklınıza gelebilecek *tüm* modern protokolleri destekler. 
*   **Freenet İçin Muazzam Potansiyeli:**
    *   **TUN Desteği:** Sistemde sanal bir ağ arabirimi (TUN) açar. Bütün Mac trafiğini yakalayıp proxy'e sokabilir (WARP'ın yaptığı işi tamamen kendi yapar).
    *   **Kural Tabanlı Yönlendirme (Routing):** "Sadece X sitelerini proxy'den geçir, Türkiye içi siteleri normal internetten çıkar" (Split Tunneling) gibi kuralları tek bir JSON dosyasıyla yapabilir.
    *   **Hedef:** İleride `wg-quick` yerine tamamen `sing-box` core'u Freenet'in içine gömülerek "Tek Motor, Sınırsız Protokol" mimarisine geçilebilir.

### 🛡️ Xray-core (ve XTLS REALITY Teknolojisi)
*   **Repo:** `XTLS/Xray-core`
*   **Mantık:** Çin'in "Büyük Güvenlik Seddi'ni" (GFW) aşmak için geliştirilmiş en sofistike projedir. 
*   **"REALITY" Özelliği (Devrimsel):** Normal bir VPN kullandığınızda (WireGuard dahil), ISP sizin "bilinmeyen bir sunucuya" bağlandığınızı bilir. Xray REALITY ise trafiği kılık değiştirir. Sanki siz Apple.com'a veya Microsoft.com'a (tamamen yasal ve güvenilir bir siteye) giriyormuşsunuz gibi **sahte bir TLS şifrelemesi** oluşturur. ISP bunu asla engelleyemez çünkü engellerse internetin yarısı çöker.
*   **Freenet'e Katkısı:** Freenet ileride kullanıcılara ücretsiz sunucular ("Topluluk Sunucuları") sağlamak isterse, Freenet içine `Xray-core` gömülüp "REALITY" protokolüyle asla tespit edilemeyen bir tünel açılabilir.

---

## 3. Menü Çubuğu (MenuBar) & VPN Yönetim Uygulamaları

Swift / macOS tarafında UI ve sistem entegrasyonu için ilham alınabilecek projeler:

### 🧩 CleverVPN (SwiftUI tabanlı)
*   **Repo:** `CleverVPN/clever-vpn-client-apple`
*   **Mantık:** macOS'un kendi yerleşik (native) `NetworkExtension` kütüphanesini kullanır. Freenet şu an komut satırı araçları (`wg-quick` ve `networksetup`) kullanıyor.
*   **Freenet'e Katkısı:** İleriki yıllarda (Faz 5), Sudoers dosyasıyla uğraşmayı tamamen bırakıp, doğrudan Apple'ın `NetworkExtension` API'si ile (kullanıcıya sistem penceresinden bir kez izin aldırarak) resmi VPN tüneli kurmak için bu reponun mimarisi kopyalanabilir. Bu, uygulamayı Mac App Store'a koyulabilir hale getirir.

---

## 💡 Sonuç ve Freenet İçin Stratejik Öneriler

1.  **DPI Motorunda Kal:** Şu an macOS için `ciadpi` + SOCKS5 ikilisi olabilecek **en hafif ve en hızlı** çözüm. Zapret veya GreenTunnel gibi maceralara girmeye hiç gerek yok. SpoofDPI ileride B planı olarak aklımızda durmalı.
2.  **WARP'ın Zayıf Noktası:** WARP (WireGuard) çok hızlıdır ama paketi gizlemez (obfuscation yapmaz). Sadece şifreler. Eğer ISS'ler Türkiye'de WireGuard protokolünün parmak izini (UDP paket başlıklarını) toptan bloklamaya başlarsa Freenet'in Tünel modu çalışmaz.
3.  **Gelecek Vizyonu (Ultimate Freenet):** Eğer Freenet'i "Asla Engellenemez" yapmak isterseniz, arka plana `sing-box` çekirdeği entegre edilmelidir. Freenet UI, `sing-box`'ı yöneten bir kontrolöre dönüşür. Böylece hem yerel DPI bypass hem de Hysteria2 / REALITY gibi sansür kıran tüneller tek bir JSON ayar dosyasıyla yönetilebilir.
