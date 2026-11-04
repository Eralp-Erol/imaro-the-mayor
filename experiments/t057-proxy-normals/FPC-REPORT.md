# Tek son F(P,C) deneyi — FROZEN / uygulayıcı REJECT önerisi

Yetki: `production/qa/T-057-technical-review.md` son bölümü. Yalnız mevcut deney
çınarının shader/import/adresleme yolu değişti. Bake, albedo, normal veri atlası,
GLB geometri/UV,LOD0,6tri/ikiTexture2D ve50/120m eşikleri değişmedi. Diğer7
adayın asset politikası ve önceki44asset/policy girdisi aynı hash’tedir.

## Sonlu sonuç

Sekiz gerçek150m kaynak/aday kare ve karşılaştırma açıldı. Önceki parlak yan
X azalıyor; üstten faset verisi kalıyor. Ancak ön150m’de düz yatay taç şeridi,
yanlara uzanan ince kart/kenar lekeleri ve kaynakla farklı taç tonu hâlâ okunur.
Yan görünüm de kaynağa göre daha düzgün/açık kalır. +60° güneşte iki temsil
ışığa tepki verir; proxy kaynak yaprak/faset kontrastını aynı biçimde korumaz.
**Bu sonuç sanat PASS’ı değildir. Sonlu koşula göre üç çapraz kart yaklaşımının
bu hedef için reddini/teknik blocker kaydını öneriyorum; uygulama durdu.**
Bağımsız art-director son hükmü verir. Yeni AO/alpha/weight/LOD düzeltmesi,
yeni bake, başka7’ye yayma veya finalfull yapılmadı.

Görüntü: `fpc-comparison-150m.png`; tam1600×900 kareler `fpc-frames.json`.
Önceki kendi-kart normal deneyi `comparison-150m.png` ve
`normal-only-before-fpc.gdshader` ile tarihî karşılaştırma olarak korunur.

## Uygulama doğruluğu ve sınırlamalar

`derive_maps.py` gerçek deney GLB’sinin POSITION/TEXCOORD_0 erişimlerinden üç
projeksiyonu ayırır. Her biri için düzlemde minimum-norm affine u/v gradyanı
üç köşeden çözülür; dördüncü köşe ve altı ikili orta nokta ile sınanır.
12köşe+18orta nokta; maksimum hata **1.39e-17 UV**. Yön/ayna/eşik işaretleri
varsayılmaz. `projection_maps.json` gerçek köşe/UV, eksen, bounds ve GLB hash’ini
kaydeder. Normal atlas ofseti640px kaynak metadata’dan okunur.

Gerçek EditorScenePostImport bu haritaları ayrı inline ShaderMaterial’a yazar;
external template’in yalnız bellekte değiştirilmesine güvenilmez. Deney GLB
importunda gereksiz otomatik LOD üretimi kapalıdır; kaynak6tri geometri aynı.
Runtime audit gerçek ithal materyal uniformlarını kaynak12köşeyle tekrar
projeksiyon kontrolüne sokar. Eksik harita alanları hata verir; bozuk map_u_0
negatif deneyi anlamlı hata/nonzero üretir (`fpc-negative-results.json`).

Shader her fragment için nesne konumuP ve güncel nesne-uzayı kameraC hesaplar.
Üç affine P→UV’den hem RGB hem normal örneklenir; kaynak örnekler geçerli
projeksiyon bounds dışına sarılmaz. Normaller decode/normalize edilir, dot(n,C)
negatifse güncel kameraya doğru bir kez yöneltilir; kart FRONT_FACING kullanılmaz.
Ağırlıklar sabit dot(C,projeksiyon_ekseni)²×kaynak alfa×geçerlilik; RGB lineer
ışıkta, normal aynı ağırlıklarla birleşir. Küçük payda/iptal normalde en yüksek
geçerli ağırlık kullanılır; bütün kapsama geçersizse fragment atılır. Yeni
küresel normal, AO, tint veya sonuçlara göre ayarlanmış sharpness yoktur.

Örtük dFdx/dFdy iki farklı kartta farklı mip seçmesin diye **ortak analitik
kamera-düzlemi piksel ayakizi** kullanılır: o P’nin view derinliği/projeksiyon ve
viewport yüksekliğinden birpiksel dünya mesafesi; camera-right/up nesneye
çevrilir, affine UV gradyanlarıyla texel ayakizi hesaplanır; log2 en büyük
uzunluk açık textureLod verir. Kartın yüz normali/UV türevi bu hesapta yoktur.
Bu kanonik ayakizi yüzün fiziksel foreshortening modeli değildir; görünüşe göre
LOD bias eklenmedi.

Tam **3albedo+3normal örneklemesi** vardır. Kart kimliği yalnız silüet alfayı
seçer: kendi affine UV’si kendi eski UV’siyle eşleştiğinden o projeksiyondaki
alfa yeniden kullanılır, yedinci fetch yoktur. Kaynak alpha texeli/UV/.45 eşiği
korunur; ortak açık LOD yüzünden önceki örtük-türev alfa mip ayakiziyle
rasterleştirilmiş kaplama byte-eşitliği iddia edilmez. Ön karedeki ince kart
kenarları bu görünürlük/kaplama sınırını da açığa çıkarır; yeni alpha araması
ile gizlenmedi. Yalnız RGB/normal alanının sürekliliği silüet/derinlik
sürekliliğini garanti etmez.

`check_fpc.py` bağımsız kaynak görüntülerinden fiziksel üç-kart kesişiminde
bilinear base-level lineer RGB/noncolor normal örneği çıkarır. AynıP/C için
üç alıcının ortak sonucu RGB+normal farkı0; eski kendi-kart normal farkı **1.601**
olan gerçek karşı örnek vardır (`fpc-numeric-continuity.json`). Bu CPU örneği
GPU piksel eşitliği veya görsel kabul kanıtı diye sunulmaz; gerçek runtime
uniform kontrolü ve açılan karelerle birlikte adresleme kusurunu sınar.

## Korunan kontroller / maliyet

Gerçek import: ikiTexture2D, altı signedXYZ readback/mip/gamma ve zemin gölgesi
kontrolleri PASS (`artifacts/verify/t057/fpc-audit.log`). Eksik/zero normal ve
bozuk affine map olmak üzere3negatif denetim nonzero/doğru tanı verir. GDScript
lint ve diff-check temiz. Kaynak normal/alpha/gamma deneyi yeniden bake edilmedi;
bilinen veri kaynakları aynı hash (`fpc-preservation.json`). Önceki47test sonucu
bu shader’ın sanat kabulü olarak taşınmaz; bu tur global/47paket çalıştırılmadı.

Ek veri Texture2D/mip maliyeti aynı **2,097,148byte**; toplam texture monitor
**66,672,914byte**.6fetch sürümü tekçınar150m/1600×900/Compatibility/RadeonPro560X,
VSync kapalı60ısınma+180örnekte ortalama **3.647ms**,P95 **5.731ms**,8drawcall
verdi (`artifacts/verify/t057/fpc-benchmark-proxy.log`). Önceki2fetch aday aynı
dar ölçümde3.529/3.704ms idi; tek tekrar/CPU frame aralığı olduğundan fark
istatistiksel GPU maliyet kıyası veya kent/iPad bütçesi değildir. Yeni render
pass/geometri/Texture2D yok; üç kat sampler işi açıkça kayıtlıdır.

## Tekrar / kareler

```
python3 experiments/t057-proxy-normals/derive_maps.py
uv run --with pillow==11.3.0 python experiments/t057-proxy-normals/check_fpc.py
tools/godot.sh --headless --path . --editor --import --quit
tools/godot.sh --headless --path . --script res://assets/hero/vegetation/normal_experiment/audit.gd
```

Harita JSON veya post-import betiği değişirse Godot varlık cache’ine dikkat:
shader uniformlarının yeni değerleri gerçekten ithal scene’e yazılmadan capture
kabul edilmez; runtime audit eksik uniformu reddeder. Temiz import aynı sonucu
üretir. Sekiz capture komutu `fpc-frames.json` içindedir.

- front / lod0 / sun+0°: `artifacts/screenshots/captures/20261027-134958-t057-fpc-plane-front-lod0-sun0.png`
- front / proxy / sun+0°: `artifacts/screenshots/captures/20261027-135002-t057-fpc-plane-front-proxy-sun0.png`
- side / lod0 / sun+0°: `artifacts/screenshots/captures/20261027-135007-t057-fpc-plane-side-lod0-sun0.png`
- side / proxy / sun+0°: `artifacts/screenshots/captures/20261027-135011-t057-fpc-plane-side-proxy-sun0.png`
- top / lod0 / sun+0°: `artifacts/screenshots/captures/20261027-135015-t057-fpc-plane-top-lod0-sun0.png`
- top / proxy / sun+0°: `artifacts/screenshots/captures/20261027-135020-t057-fpc-plane-top-proxy-sun0.png`
- front / lod0 / sun+60°: `artifacts/screenshots/captures/20261027-135024-t057-fpc-plane-front-lod0-sun60.png`
- front / proxy / sun+60°: `artifacts/screenshots/captures/20261027-135028-t057-fpc-plane-front-proxy-sun60.png`
