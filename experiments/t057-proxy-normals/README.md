> Son sınırlı F(P,C) sonucu: [FPC-REPORT.md](FPC-REPORT.md). Uygulayıcı görsel sorunun sürdüğünü kaydetti; deneme frozen, yeni batch yok. Aşağıdaki bölüm önceki normal-only deneyi anlatır.

# T-057 tek çınar kaynak-normal deneyi — FROZEN / görsel sorun sürüyor

Yetki: `production/qa/T-057-technical-review.md`. Yalnız bir çınar/3kart/6tri;
bütçe,50/120m,LOD0 tasarımı, ana albedo ve diğer7 aday değiştirilmedi.
Bu prototip ana katalog/pipeline’a geçirilmedi. Bağımsız sanat kararı beklenir;
uygulayıcı kalan yan-görünüm kusuru nedeniyle deneyi burada durdurdu.

## Sonuç / sonlu durma nedeni

Gerçek150m ön/yan/üst ve +60° güneş azimutu ön kaynak/proxy çifti açıldı.
Kaynak-normal verisi yaprak/faset ışık çeşitliliğini geri getiriyor; sabit açık
yeşil damga ve üstten koyu X önceki adaya göre gideriliyor. İki temsil de
alternatif güneşe tepki veriyor. Ancak yan150m proxy’de kaynakta olmayan parlak
çapraz/yatay şerit, üç kaynak projeksiyonun kesişiminde hâlâ okunuyor. Üstten
ton/örtüşme de kaynakla aynı değil. **Görsel PASS verilmez; diğer7’ye yayılmaz.**
Bütün8kanıt/contact/full bu deney için yapılmadı; yeni AO/tint/normal düğmesi
veya kaynak LOD0 değişikliği denenmedi. Sonraki temsil seçimi yeni director
kararı gerektirir. `comparison-150m.png` sekiz gerçek karenin küçültülmüş
karşılaştırmasıdır; ham tam1600×900 kareler `frames.json` içinde.

## Gerçek kaynak ve eksen/gamma kanıtı

`bake_normals.py` kaynak GLB POSITION/NORMAL verisini doğrudan okur.
Blender içe aktarımı3072 gerçek köşede sınandı: en büyük normal vektör farkı
0.0001000585 (Blender custom-normal quantization). Bake bu yaklaşık kopya
normalini değil, karşılık gelen **ham glTF NORMAL** değerini kullanır.
Y-up→Z-up `(x,-z,y)`, geri `(x,z,-y)`; altı ±eksen sentinel roundtrip temiz.
Her projeksiyonda kaynak çift-taraf yüzünün kameraya bakan etkin işareti bir
kez uygulanır. Godot4.7.2 Compatibility renderer aynı arka-yüz terslemesini
custom fragment kodundan önce yapar; shader’ın yeni NORMAL yazımı bunu tekrar
terslemez ([aynı ed1daf0bf kaynak](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/drivers/gles3/shaders/scene.glsl)).

Emission yalnız sayısal normal kodlama içindir; güneş/albedo/gölge bake edilmez.
Raw PNG sentinel .25/.5/.75→(64,127,191), ±1byte içinde doğrulandı. Üç görünüm
orijinal kamerayı, fiziksel kırpmayı,112² içerik+8px kenarı kullanır. .45 kaynak
alfa maskesi3/3 aynıdır. Raw üst geçişte48 antialias alfa byte’ı değişse de .45
maskesi değişmez; pack filtre ağırlığı ayrıca orijinal albedo-capture alfasından
alınır. Çalışma zamanı alpha **değişmeyen özgün albedo atlasından** okunur.
RGB normal vektörü alpha-aware nötr çevresinde filtrelenir; veri A=1/rezerve.
Her görünümde>100 farklı RGB değeri doğrulanır; provenance `normal_capture.json`.

## Gerçek import/materyal ve maliyet

`assets/hero/vegetation/normal_experiment/` yalnız deney içindir. `plane_proxy.glb`
aynı kaynak geometri/normal/UV/indeks/BIN’i taşır; yalnız albedo URI’si mevcut
kanonik atlası gösterecek şekilde yeniden yazılmıştır. `.glb.import` gerçek
`import.gd` EditorScenePostImport’u kullanır; `normal_proxy.tres/.gdshader`
varlığın materyalidir. `lab.gd` materyali değiştirmez, bu gerçek ithal varlığı
seçer; alternatif güneş her iki seviye için aynı +60°’dir.

Shader RGB→[-1,1] açar/normalize eder; küçük/mipte iptal olmuş vektörlerde Y-up
fallback kullanır. Model normal matrisi→view dönüşümü doğru sıradadır. Veri
sampler’ında source_color/hint_normal yoktur; tangent map veya mavi bileşen
rekonstrüksiyonu yapılmaz. Lossless RGBA8, normal_map=Disabled(2), otomatik3D
compression kapalı ve mips açık. Gerçek ithal Texture2D readback altı ±XYZ
sentinel’i, özellikle negatif mavi bileşeni bayt eşit korur. Albedo aynı gerçek
Texture2D; asset iki sampler/iki Texture2D kullanır. Sabit AO/emission/unlit yok.

MASK0.45, mat Lambert/roughness1/specular0, çift taraf ve shadows_disabled
korunur; proxy gölge almaz ama zemine çift taraf alpha-silüet gölgesi atar.
Bu politika bina/ağaç gölgesini de almaz; source self-shadow eksikliğini
normal-only capture bütünüyle yeniden kurmaz. AA: viewport4×MSAA, kaynak lab
coverage, deney shader’ı alpha-scissor; miras alınan PNG başlığı lab presetini
söyler, shader’a alpha_to_coverage özelliği eklendiği anlamına gelmez.

Veri atlası1024×384RGBA8, PNG **52,776byte**; teorik mipler **2,097,148byte**
(~2.00MiB), albedo+mip toplamı ~7.33MiB. Bir ek veri örneklemesi/piksel;
yeni render pass yok. Kaynak6tri proxy geometri bütçesi değişmez.
Dar lab1600×900,AMD RadeonPro560X,Compatibility,VSync kapalı60ısınma+180örnek:

| Yalnız tek çınar150m | Ortalama ms | P95 ms | Drawcall | Texture monitor byte |
|---|---:|---:|---:|---:|
| LOD0 | 3.566 | 3.704 | 8 | 64,575,766 |
| Deney proxy | 3.529 | 3.704 | 8 | 66,672,914 |

Texture monitor farkı **2,097,148byte**, teorik ek veri mip maliyetiyle aynı.
Bu dar örnek istatistiği GPU timer, hızlanma iddiası veya kent/iPad bütçesi
kanıtı değildir. Benchmark logunun eski `context:street` varsayılan etiketi
bu komutta gerçek sokak anlamına gelmez: `--context` verilmedi, tek çınardır.

## Kontroller ve tekrar komutları

```
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python experiments/t057-proxy-normals/bake_normals.py
uv run --with pillow==11.3.0 python experiments/t057-proxy-normals/pack_normals.py
tools/godot.sh --headless --path . --editor --import --quit
tools/godot.sh --headless --path . --script res://assets/hero/vegetation/normal_experiment/audit.gd
```

Gerçek import audit PASS:2 Texture2D/6signedXYZ sentinel/mips/ground-shadow.
`--negative=missing` ve `--negative=zero` aynı audit’te anlamlı hata/nonzero
çıkarır (`negative-results.json`). `pack-determinism.json`: mevcut değişmeyen
normal capture’larından tekrar pack edilen3 dosya hash eşit; tam normal render
tekrarı yapılmadı. `artifacts/verify/t057/normal-experiment-preservation.json`:
eski81 kayıt+67GLB+14PNG ve önceki44asset/policy dosyası değişmedi. Böylece ana
LOD0/atlas/proxy zinciri ve diğer7 aday korunur. Deney GDScript lint temiz.
Broad quick/full ve commit/push yok. Final T-057 sanat kapısı kapanmadı.

## Gerçek kareler

- front / lod0 / sun+0°: `artifacts/screenshots/captures/20261027-123137-t057-normal-plane-front-lod0-sun0.png`
- front / proxy / sun+0°: `artifacts/screenshots/captures/20261027-123142-t057-normal-plane-front-proxy-sun0.png`
- side / lod0 / sun+0°: `artifacts/screenshots/captures/20261027-123146-t057-normal-plane-side-lod0-sun0.png`
- side / proxy / sun+0°: `artifacts/screenshots/captures/20261027-123150-t057-normal-plane-side-proxy-sun0.png`
- top / lod0 / sun+0°: `artifacts/screenshots/captures/20261027-123154-t057-normal-plane-top-lod0-sun0.png`
- top / proxy / sun+0°: `artifacts/screenshots/captures/20261027-123158-t057-normal-plane-top-proxy-sun0.png`
- front / lod0 / sun+60°: `artifacts/screenshots/captures/20261027-123202-t057-normal-plane-front-lod0-sun60.png`
- front / proxy / sun+60°: `artifacts/screenshots/captures/20261027-123207-t057-normal-plane-front-proxy-sun60.png`
