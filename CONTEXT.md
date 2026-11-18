# Freenet

Freenet, macOS kullanıcılarına sansür aşma ve IP maskeleme arasında açık bir seçim sunan internet özgürlüğü ürünüdür. Kullanıcı neyin korunduğunu ve neyin korunmadığını bir Niyet seçerek belirler.

## Language

**Niyet**:
Kullanıcının hız, IP görünürlüğü ve aracıya güven arasındaki tercihini ifade eden bağlantı duruşu. Bir Niyet başka bir Niyete kullanıcı onayı olmadan düşürülemez.
_Avoid_: Mod, profil, motor

**Hızlı Erişim**:
Gerçek IP adresini gizlemeden doğrudan bağlantı yolunda sansür aşmayı hedefleyen Niyet.
_Avoid_: Hızlı mod, anonim bağlantı

**Dengeli Tünel**:
Gerçek IP adresini hedeflerden maskeleyen, ancak tek bir tünel operatörüne güven gerektiren Niyet.
_Avoid_: Gizlilik modu, anonim tünel, VPN anonimliği

**Motor**:
Bir Niyetin ağ davranışını gerçekleştiren değiştirilebilir teknik mekanizma. Kullanıcı ürün yüzeyinde Motor değil Niyet seçer.
_Avoid_: Niyet, mod

**IP Maskeleme**:
Hedef hizmetlerin kullanıcının gerçek IP adresi yerine bir tünel operatörünün adresini görmesi. Tek başına anonimlik anlamına gelmez.
_Avoid_: Anonimlik, kimlik gizleme

**DPI Atlatma**:
Belirli DPI sistemlerinin alan adı veya protokol eşlemesini bozmak için bağlantının iletim biçimini değiştirme. Kaynak ve hedef IP adreslerini gizlemez.
_Avoid_: DPI paketlerini yok etme, anonimleştirme, izlenemezlik

**Anonimlik**:
Bir gözlemcinin kullanıcı kimliği ile ağ etkinliği arasında güvenilir bağ kuramaması. Freenet'in mevcut doğrudan bağlantı ve tek-operatör tünel Niyetleri bu korumayı sağlamaz.
_Avoid_: DPI atlatma, IP maskeleme, şifreleme
