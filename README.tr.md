# 🛡️ Freenet (macOS)

**Freenet**, Türkiye'deki internet sansürlerini ve IP bloklamalarını aşmak için geliştirilmiş, tamamen açık kaynaklı ve dışa bağımsız bir **Hibrit (DPI + Tünel)** macOS menü çubuğu uygulamasıdır. 

Windows tarafındaki efsanevi GoodbyeDPI mimarisinden ilham alınarak macOS'a uyarlanmıştır. Herhangi bir üyelik, kayıt veya ücret gerektirmez.

---

## ✨ Özellikler

Freenet, sansür yöntemlerine karşı iki farklı motor (mod) sunar:

### 1. 🚀 DPI Modu (Yerel Motor - ciadpi)
* **Nasıl Çalışır:** Arka planda SOCKS5 tabanlı yerel bir proxy açarak (127.0.0.1:1080) paketlerinizi parçalar. İnternet servis sağlayıcınızın koyduğu SNI (Server Name Indication) filtrelerini aşmanızı sağlar.
* **Avantajı:** Hiçbir dış sunucuya (VPN'e) bağlanmaz! Trafiğiniz doğrudan hedefe gider. Bu nedenle **hız kaybı sıfırdır**. YouTube, X (Twitter) gibi DPI sansürü olan sitelere tam hızda girersiniz.
* **Not:** Anonimlik sağlamaz. Sadece sansürü deler.

### 2. 🌍 Tünel Modu (WARP - wg-quick)
* **Nasıl Çalışır:** Eğer erişmek istediğiniz site (Örn: Discord) DPI filtresiyle değil de **doğrudan IP engellemesi** ile kapatılmışsa, DPI motoru işe yaramaz. Bu durumda menüden "Tünel Modu"nu seçersiniz. Sistem tamamen ücretsiz olan Cloudflare WARP ağı üzerinden WireGuard tüneli kurar.
* **Avantajı:** Gerçek kimliğinizi ve IP'nizi yurt dışına taşır. Tüm engelleri kesin olarak aşar.

### ⚡️ Şifresiz Tek Tıkla Geçiş (Sudoers IPC)
VPN ve DPI araçları macOS'ta `sudo` (Yönetici) izni gerektirir. Freenet, ilk açılışta sizden bir kereye mahsus izin isteyerek sisteminize özel ve güvenli bir `sudoers` dosyası kurar. Artık menüden sadece tek tıkla **sıfır saniyede ve şifre girmeden** modlar arası geçiş yapabilirsiniz.

---

## 📦 Kolay Kurulum

Uygulamayı Mac'inize yüklemek için Terminal'i (Uygulamalar > İzlenceler > Terminal) açın ve aşağıdaki komutları sırasıyla yapıştırıp `Enter`'a basın:

```bash
# 1. Projeyi bilgisayarınıza indirin
git clone https://github.com/Baro007/freenet.git
cd freenet/app

# 2. Uygulamayı derleyin ve yükleyin
./build.sh
cp -R build/freenet.app /Applications/
xattr -dr com.apple.quarantine /Applications/freenet.app

# 3. Freenet'i başlatın
open /Applications/freenet.app
```

*Not: Uygulama çalıştıktan sonra Mac'inizin üst sağ köşesinde (saatin yanında) küçük bir kalkan 🛡️ ikonu belirecektir.*

---

## 🛠️ İlk Kullanım

1. Kalkan ikonuna tıklayın.
2. Açılan menüden **"Şifresiz Geçişi Aktif Et ⚡️"** seçeneğine tıklayın.
3. Mac şifrenizi girin.
4. Artık kalkan ikonuna basıp **AÇ / KAPAT** diyerek sansürsüz internetin keyfini çıkarabilirsiniz!
5. **Bağlantı Modu** altından hız için `DPI`, gizlilik için `Tünel (WARP)` seçebilirsiniz. En üst kısımda IP adresinizin başarıyla değiştiğini görebilirsiniz.

---

## 🤝 Krediler ve Teşekkürler

Freenet, açık interneti savunan aşağıdaki özgür yazılım projelerinin omuzlarında yükselmektedir:
- [ciadpi (ByeDPI)](https://github.com/hufrea/byedpi) - DPI atlatma motoru.
- [WireGuard](https://www.wireguard.com/) & [Cloudflare WARP](https://1.1.1.1/) - Tünel altyapısı.
- [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) & [SplitWire-Turkey](https://github.com/a-mertdincer/SplitWire-Turkey-macOS) - İlham alınan topluluk projeleri.
