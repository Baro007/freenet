# 🛡️ Freenet (macOS)

<p align="center">
  <img src="assets/banner.png" alt="Freenet Afiş" width="100%">
</p>

<p align="center">
  <a href="https://img.shields.io/badge/Platform-macOS%2013.0+-apple?style=flat-square&logo=apple"><img src="https://img.shields.io/badge/Platform-macOS%2013.0+-apple?style=flat-square&logo=apple"></a>
  <a href="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift"><img src="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift"></a>
  <a href="https://img.shields.io/badge/License-MIT-green?style=flat-square"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square"></a>
</p>

<h3 align="center">Sansürü aşın. Hesap yok. Abonelik yok. Sadece tıklayın.</h3>

Freenet, macOS için özel olarak Swift ile geliştirilmiş, **sıfır ayar** gerektiren hibrit bir internet özgürlüğü aracıdır. Efsanevi GoodbyeDPI projesinden ilham alınarak Mac menü çubuğuna (menubar) kusursuzca entegre edilmiştir. 

🇬🇧 **[Click here for English Documentation](README.md)**

---

## ✨ Neden Freenet? (Nasıl Çalışır?)

Sansür sistemleri tek tip değildir. Freenet, karşılaştığınız engele göre kullanabileceğiniz iki farklı motor sunar:

### 1. 🚀 DPI Modu (Hız ve Performans Odaklı)
*   **Sorun:** Türkiye'deki sansür sistemi genellikle bir kargocu (İSS) gibi çalışır. Paketin üstünde "yasaklisite.com" yazıyorsa kargoyu çöpe atar (DPI - Derin Paket İncelemesi).
*   **Çözüm:** Freenet DPI modunu açtığınızda arka planda paketinizin üzerindeki yazıyı jiletle keser. "yasak" ve "lisite.com" olarak iki ayrı parça halinde gönderir. İSS'nin filtreleri bu kopuk parçaları okuyamadığı için paketin geçişine izin verir.
*   **Sihir:** Trafiğiniz hiçbir aracı sunucuya (VPN'e) gitmez! Bağlantınız doğrudan karşı tarafadır. Bu yüzden **%0 hız kaybı** yaşarsınız. Hız testiniz 100 Mbps ise, yasaklı siteye de 100 Mbps ile girersiniz. *(Not: IP adresiniz gizlenmez, sadece sansürü atlatır).*

### 2. 🌍 WARP Tünel Modu (Ağır Zırhlı Mod)
*   **Sorun:** Bazen devletler sadece isimden değil, sitenin doğrudan adresinden (IP Ban) engelleme yapar. Bu durumda kargo etiketini parçalamak işe yaramaz.
*   **Çözüm:** Freenet, dünyanın en büyük internet altyapılarından biri olan Cloudflare sunucularına doğrudan şifreli bir "boru" (WireGuard Tüneli) döşer. Sizin tüm trafiğiniz bu aşılmaz borunun içinden geçer.
*   **Sihir:** IP banlı siteleri anında açar. Sizi anonim yapar (IP adresiniz Cloudflare'in IP'si gibi görünür). Ortak Wi-Fi ağlarında sizi bilgisayar korsanlarından korur.

---

## 🎩 Freenet'in "Sihirli" Özellikleri

Freenet sadece bir komut aracı değil, Mac'inizin yerleşik bir parçası gibi hissettiren bir otopilottur.

*   **⚡ Sıfır Sürtünme Kurulum:** Yeni bir kullanıcı "Tünel Modu"na ilk bastığında, Freenet arkada sessizce gerekli programları (Homebrew, wireguard) indirir, Cloudflare'e bağlanıp ücretsiz profil oluşturur. Sizin Terminal'e tek bir kod yazmanıza gerek kalmaz.
*   **🔓 Şifresiz Geçiş (Tek Tık):** Normalde ağ ayarlarını değiştirmek Mac'te sürekli şifre ister. Freenet, ilk kurulumda sisteme güvenli bir izin bırakır. Artık VPN açıp kapatmak saniyeler sürer, asla şifre sormaz.
*   **🧠 Kendi Kendini İyileştirme (Self-Healing):** Mac'in kapağını kapattınız veya Wi-Fi ağı değiştirdiniz ve bağlantı koptu mu? Freenet bunu saliseler içinde fark edip Tünel'i kendi kendine yeniden başlatır. Asla internetsiz kalmazsınız.
*   **📊 Canlı Dashboard:** Teknik detayları sevenler için arkada paketlerin nasıl parçalandığını gösteren "Matrix" tarzı canlı bir log ekranı sunar.

---

## 📦 Tek Komutla Kurulum

Freenet'i kurmak için Mac'inizde Terminal'i (`Uygulamalar > İzlenceler > Terminal`) açın ve şu tek satır kodu yapıştırıp Enter'a basın:

```bash
curl -fsSL https://raw.githubusercontent.com/Baro007/freenet/main/install.sh | bash
```

*Bu komut uygulamayı indirecek, derleyecek ve `Uygulamalar` klasörünüze yerleştirip otomatik başlatacaktır.*

---

## 🤝 Krediler ve İlham Kaynakları
- [ciadpi (ByeDPI)](https://github.com/hufrea/byedpi) - Çekirdek DPI atlatma motoru.
- [WireGuard](https://www.wireguard.com/) & [Cloudflare WARP](https://1.1.1.1/) - Tünel altyapısı.
- [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) & [SplitWire-Turkey](https://github.com/a-mertdincer/SplitWire-Turkey-macOS) - Fikir ve ilham kaynakları.

## 📝 Lisans
MIT License. Detaylar için [LICENSE](LICENSE) dosyasına bakabilirsiniz.
