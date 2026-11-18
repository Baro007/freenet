# DPI atlatma ile anonimlik aynı şey mi?

Tarih: 2026-07-19

## Kısa hüküm

**Hayır.** ByeDPI/`ciadpi` ve sing-box TLS/TCP parçalama, bazı DPI sistemlerinin `ClientHello`, SNI veya HTTP `Host` bilgisini doğru eşlemesini zorlaştırarak **sansür aşma** ve sınırlı bir **metadata gizliliği** kazanımı sağlayabilir. Ancak bunlar kullanıcıyı anonimleştirmez, gerçek IP'yi maskelemez ve ISP'nin abone ile hedef IP arasındaki bağlantıyı izlemesini engellemez.

“DPI paketlerini yok etmek” teknik olarak doğru bir tarif değildir. DPI ayrı bir paket türü üretmez; geçen normal ağ paketlerini inceler. ByeDPI, paketlerin bölünme/sıralanma biçimini veya TLS record sınırlarını değiştirip basit ayrıştırıcıları yanıltır; geçerli gerçek veri akışı yine hedef sunucuya ulaşır. Projenin kendi tanımı da `ciadpi`yi “DPI bypass methods” uygulayan **yerel SOCKS proxy** olarak verir ve `split`, `disorder`, `fake` ile `tlsrec` yöntemlerinin nasıl çalıştığını açıklar ([resmî ByeDPI README](https://github.com/hufrea/byedpi#readme)).

## Koruma sınırları

| Özellik | DPI parçalamanın etkisi |
|---|---|
| HTTPS içerik gizliliği | İçeriği TLS şifreler; fragmentation yeni bir şifreleme katmanı eklemez. TLS'nin güvenli kanal hedefi içerik gizliliği ve bütünlüğüdür ([RFC 8446 §1](https://datatracker.ietf.org/doc/html/rfc8446#section-1)). |
| Sansür aşma | Basit DPI/firewall, SNI veya `Host` tek parçada değilse eşleşmeyi kaçırabilir. sing-box bu özelliği TLS el sıkışmasını parçalayarak firewall atlatma olarak tanımlar ve paket parçalamayı yalnızca basit plaintext eşleşmeli firewall'lar için konumlandırır ([sing-box `tls_fragment`](https://sing-box.sagernet.org/configuration/route/rule_action/#tls_fragment), [`tls_record_fragment`](https://sing-box.sagernet.org/configuration/route/rule_action/#tls_record_fragment)). |
| SNI gizliliği | **Koşullu ve kırılgan.** SNI şifrelenmez; plaintext `ClientHello` içinde kalır ([RFC 6066 §3](https://datatracker.ietf.org/doc/html/rfc6066#section-3), [RFC 8744 §2](https://datatracker.ietf.org/doc/html/rfc8744#section-2)). TLS, handshake mesajlarının birden çok record'a bölünmesini ve alıcıda yeniden birleştirilmesini zaten destekler; stateful bir gözlemci de aynı yeniden birleştirmeyi yapabilir ([RFC 8446 §5.1](https://datatracker.ietf.org/doc/html/rfc8446#section-5.1)). Bu nedenle sonuç “SNI yok oldu” değil, “bazı DPI ayrıştırıcıları SNI'yi çıkaramayabilir”dir. |
| DNS alan adı gizliliği | Fragmentation DNS'i kendiliğinden korumaz. DoH, istemci–resolver arasındaki DNS sorgusuna TLS gizliliği sağlar ([RFC 8484 §1](https://datatracker.ietf.org/doc/html/rfc8484#section-1)); resolver yine sorguları görebilir ve şifreli DNS boyut/zamanlaması korelasyona açıktır ([RFC 9076 §5–6](https://datatracker.ietf.org/doc/html/rfc9076#section-5)). |
| Hedef IP/port | Gizlenmez. IP başlığı kaynak ve hedef adresini, TCP başlığı portları taşır ([RFC 9293 §3.1](https://datatracker.ietf.org/doc/html/rfc9293#section-3.1)). SNI görünmese bile hedef IP çoğu durumda servis veya servis kümesi hakkında sinyal verir ([RFC 8744 §2.2](https://datatracker.ietf.org/doc/html/rfc8744#section-2.2)). |
| Abone kimliği | Gizlenmez. Yerel ISP, doğrudan trafikte bağlantının kendi abonesinden çıktığını ve hangi hedef IP'ye gittiğini ilişkilendirebilir; yerel packet/record dönüşümü bu yolu değiştirmez. Tor Project'in doğrudan IP yönlendirmesi açıklaması, her yönlendiricinin hedef adresi gördüğünü ve yerel ISP'nin kullanım profili çıkarabilecek konumda olduğunu belirtir ([Tor koruma modeli](https://support.torproject.org/about-tor/introduction/protections/)). |
| Trafik analizi | Engellenmez. TLS bile veri uzunluğunu gizlemez; boyut ve zamanlama trafik analizinde kullanılabilir ([RFC 8446 §1 ve Ek E.3](https://datatracker.ietf.org/doc/html/rfc8446#appendix-E.3)). IETF, metadata, zamanlama, boyut ve korelasyonu ayrıca pervasive monitoring kapsamına alır ([RFC 7258 §1–2](https://datatracker.ietf.org/doc/html/rfc7258#section-1)). |
| IP maskeleme | Sağlanmaz. Bunun için trafiğin uzak bir VPN/proxy/relay çıkışından internete çıkması gerekir. sing-box `direct` outbound istekleri doğrudan gönderir ([resmî sing-box `direct` belgesi](https://sing-box.sagernet.org/configuration/outbound/direct/)). |
| Anonimlik | Sağlanmaz. Anonimlik için kimlik ile etkinlik arasındaki bağın kopması gerekir. Karşılaştırma amacıyla Tor, trafiği birden çok relay üzerinden geçirerek hiçbir tek noktanın hem kaynağı hem nihai hedefi görmemesini amaçlar ([Tor koruma modeli](https://support.torproject.org/about-tor/introduction/protections/)). Fragmentation'da böyle bir relay veya güven ayrıştırması yoktur. |

## Neden gelişmiş DPI tekrar okuyabilir?

ByeDPI `--tlsrec` ile bir TLS record'u SNI ortasında birden çok record'a ayırır; `--split` ve `--disorder` TCP teslim biçimini değiştirir. Bunlar, eksik TCP/TLS state takibi yapan middlebox'ları şaşırtır ([resmî ByeDPI README](https://github.com/hufrea/byedpi#readme)). Fakat TLS standardı handshake mesajlarının record'lar arasında parçalanmasını geçerli sayar ve alınan verinin doğrulanıp yeniden birleştirilmesini tarif eder ([RFC 8446 §5 ve §5.1](https://datatracker.ietf.org/doc/html/rfc8446#section-5.1)).

Dolayısıyla aşağıdaki sonuç bir **standart ve uygulama davranışından çıkarımdır**: hedef sunucunun yaptığı yeniden birleştirmeyi yeterince gelişmiş, stateful bir DPI da yapabilir. Fragmentation kriptografik gizleme değil, ayrıştırıcı uyumsuzluğundan yararlanan bir desynchronization tekniğidir.

## Freenet'in mevcut koduna eşleme

### `DPIEngine` / ciadpi

- [`DPIEngine.swift`](../../app/DPIEngine.swift) `ciadpi`yi aynı Mac'te çalıştırıp `127.0.0.1` SOCKS adresini sistem ayarlarına verir; uzak çıkış veya tünel oluşturmaz.
- [`DPIArgsValidator.swift`](../../app/DPIArgsValidator.swift) içindeki varsayılan argüman `-d 1 -p 1080`'dir. Yani varsayılan davranış `disorder` + yerel porttur; `tlsrec` varsayılan değildir. Kullanıcıya açılan izinli argümanlar bazı ek desynchronization tekniklerine izin verir.
- Motorun `privacyLevel` değeri kodda `.none` olarak işaretlidir. Bu, mevcut doğrudan bağlantı mimarisiyle tutarlıdır.
- [`ProxyService.swift`](../../app/ProxyService.swift) yalnızca macOS SOCKS proxy ayarını Wi-Fi/Ethernet için değiştirir. Tüm uygulamaların, yerel DNS'in, UDP/QUIC'in veya SOCKS ayarını yok sayan trafiğin kapsandığını kanıtlayan bir TUN/DNS-hijack mekanizması yoktur.

Sonuç: ciadpi modu bazı SNI/`Host` tabanlı blokları aşabilir; site gerçek çıkış IP'sini, ISP ise abone–hedef IP akışını görmeye devam eder.

### `SingBoxEngine`

- [`SingBoxEngine.swift`](../../app/SingBoxEngine.swift) yerel SOCKS inbound açar, port 443 için `tls_record_fragment` uygular ve outbound'u açıkça `type: direct` seçer. sing-box belgelerine göre `direct`, isteği doğrudan gönderir ([resmî belge](https://sing-box.sagernet.org/configuration/outbound/direct/)); dolayısıyla IP maskeleme yoktur.
- Yapılandırmada Cloudflare DoH sunucusu bulunur. Bu, sing-box'ın kendi yaptığı alan adı çözümlemelerinde DNS sorgusunu şifreleyebilir; fakat yalnızca `dns` bloğunun bulunması, bütün macOS DNS trafiğinin ele geçirildiğini göstermez. Kodda `hijack-dns`, TUN veya sistem DNS yapılandırması yoktur. sing-box da DNS modülünü ayrı sunucu/routing yapısı olarak tanımlar ([resmî DNS yapılandırması](https://sing-box.sagernet.org/configuration/dns/)).
- DoH kullanılan akışlarda yerel ISP DNS sorgusunun içeriğini doğrudan okuyamaz; yine de Cloudflare resolver sorguyu alır, ISP Cloudflare bağlantısını ve sonraki hedef IP bağlantısını görür, boyut/zamanlama korelasyonu kalır ([RFC 8484 §8](https://datatracker.ietf.org/doc/html/rfc8484#section-8), [RFC 9076 §5](https://datatracker.ietf.org/doc/html/rfc9076#section-5)).

Sonuç: sing-box modu, ciadpi gibi sansür aşma odaklı doğrudan bağlantıdır; DoH sınırlı DNS metadata koruması ekleyebilir ama anonimlik sağlamaz.

## Ürün dili için karar

Kullanıcının sezgisindeki doğru kısım şudur: **DPI desynchronization, ISP'nin kullandığı bazı basit inceleme mekanizmalarının alan adını çıkarmasını veya blok kuralını uygulamasını engelleyebilir.** Bu, gerçek ve değerli bir gizlilik/sansür direnci kazanımıdır.

Fakat “ISP seni izleyemez” ve “anonimlik sağlar” ifadeleri teknik olarak fazla geniştir. Freenet için savunulabilir ifade:

> Freenet, desteklenen bağlantılarda DPI tabanlı engellemeyi aşar ve alan adı bilgisinin basit DPI sistemlerince okunmasını zorlaştırabilir. HTTPS içeriğini TLS korur. Hızlı mod gerçek IP'nizi maskelemez; ISP'nize karşı tam görünmezlik veya anonimlik sağlamaz. Hedef IP, zamanlama ve trafik hacmi görünür kalabilir.

Bu sınır, DPI atlatmanın sağladığı gizlilik katkısını küçültmez; onu **anonimlik**, **IP maskeleme** ve **izlenemezlik** gibi daha güçlü ve kanıtlanmamış vaatlerden ayırır.
