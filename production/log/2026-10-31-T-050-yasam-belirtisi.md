# T-050 yaşam belirtisi: araç + yaya (görünür oyun 4/4) — 2026-10-31

REQ: WLD-01/TEK-03 (tek dünya; yoğunluk dünya/sim verisinden), SIM-01 (hane/bina verisi okunur), VIS-02, TEK-01/02 (görünüm sim'e yazmaz) · Kararlar: D-012 (araç = `veh_car`), D-013 (insan = B blok figür) · Kütüphane kapısı: yalnız onaylı kimlikler.
Taban: `60453b3` (agent/handover-imaro-m01-349562fb) birleştirildi; WIP `24957eb` tamamlandı. Kanon dizini, `data/politics/blocs.json`, `playable.gd` (1000 satır) DEĞİŞMEDİ; sim DEĞİŞMEDİ.

## Ne var (kısa)
- **Kaynak:** `LifeEdgeActivity` kenar (yol parçası) başına faaliyeti cephe parsellerinin sim birimlerinden hesaplar: biten konut birimi x bölge doluluğu (`economy_outcome`: housed/units) x w_res + biten ticaret x w_com + inşaat birimi x w_con; komşu kenarlardan `spill_share` payı. Aktivite sıfırsa araç/insan SIFIR (sahte trafik yok). Seed yalnız konum/faz üretir; sayıyı değiştirmez, sayı arttıkça eski örnek yerinden oynamaz.
- **Sim okuyucu:** `LifeSimReader` yalnız okuma sorguları (T0 stoku, `parcel_changes_since`, `parcel_views`, `economy_outcome`); komut/yazma yok; kare başı parsel tavanı; kayıt yükleme sonrası kamera yakını hücreler lazy yeniden okunur.
- **Varlıklar:** `LifeAssets` kimlikleri yalnız `LibraryGate.load_life()` (game_vehicles + game_humans) üzerinden alır: `veh_car`, `hum_hero_block_neutral_a`, `hum_hero_block_broad_a`. Piyon/faset/eski kit insanı kapıdan geçmez (testli). `build_game_set.py` bu iki tabloyu üretir (veh_car tek LOD, kit paleti).
- **Çizim:** hücre (256 m) başına en çok 5 MultiMeshInstance3D (araç; nötr/geniş x LOD0/LOD1). Hareket gölgelendiricide (`life_motion.gdshaderinc`, uniform `life_t`): CPU'da kare başı örnek güncellemesi YOK. Menzil dışı hücre hiç kurulmaz (araç 900 m, insan 230 m; dokunmatik 600/160), menzil içinde örnek başına mesafe gölgelendiricide çökertilir, gölge düşürmez.
- **Bağlama:** `scenes/game/playable.tscn` içinde `Life` düğümü (`life_host.gd`); `playable.gd` değişmedi. Başsızda kurulmaz (`--life-force` ile zorlanır). Dev: `--no-life`, `--life-density=X`, `--life-profile=touch`, `--life-time=S`, `--life-settle`.
- **Yol ağı değişimi:** `graph_version` değişince (oyuncu yolu / geri alma) yol görünümü bitince kenar dizini yeniden kurulur, yeni yol bağlandığı yollardan hemen pay alır.

## Bu oturumda yapılan
Taban birleşti (çatışma yok). Bulgular ve düzeltmeler: `life_assets.gd` açıklamasındaki eski kit insanı kimliği `no_rejected_reference_scan_test`'i kırıyordu -> kaldırıldı; `LifeHost._try_start` bölündü (gdlint max-returns); `LifeEdgeActivity` değişken sırası (gdlint); satır uzunlukları; `LifeConfig.load_path` olmayan dosyada motor hatası basmaz; `tools/verify-areas.tsv` içine `src/view/life` ve `tests/view/life` eşlemesi; probe'a A/B + yakın plan hareket kanıtı.
Testler (yeni, 36 gdUnit + 3 python): `tests/view/life/` config (8), assets (5), activity+layout (11), sim reader (5, gerçek `SimFacadeImpl` ikiz dünya: okuma `state_hash`i değiştirmez), view (7, `playable.tscn` Life düğümü + 1000 satır sınırı dahil); `tests/library/test_game_set.py` +3 (araç/insan tabloları).

## Gerçek runtime görüntüleri (pencereli, 1600x900, gerçek Ismeral, `--demo`; probe `tools/godot/life_probe.gd`)
`/private/tmp/claude-501/t050_screens/c-*.png`: `c-street` (38 m, sokak: araçlar şeritte, kaldırımda yayalar), `c-neigh` (320 m: araçlar küçük beyaz noktalar), `c-car` + `c-car_t1` (aynı kamera, saat +1 sn: araç ~7,5 m ilerliyor, ikinci araç giriyor), `c-person` + `c-person_t1` (saat +3 sn: yayalar kaldırımda yürüyor). İlçe ölçeğinde (900 m ötesi) araç/insan yok (menzil: uzaktan görünmez).
Görüleni dürüstçe: araçlar tek model, çoğu krem/bej (kit paletinin `veh_car` duvar satırları; renk çeşitliliği ve araç tipi sayısı AÇIK, D-012/Q-018); yayalar küçük, iki gövde (nötr/geniş) ayırt edilebilir. Parça sonunda araç/insan küçülüp kaybolur ve parça başında belirir (basit akış, bilinen kusur; kavşak/rota M3). Araçlar birbirinden kaçınmaz (trafik M3). Sanat/kullanıcı görsel kabulü HENÜZ YOK.

## Ölçüm (Intel i7 Mac, iGPU; iPad DEĞİL; yük ortalaması 13-25, paralel ajanlar -> gürültülü)
Aynı dünyada, aynı kamerada araya serpiştirilmiş A/B (yaşam görünümü açık/kapalı), 14 tur x 25 kare:

| poz | medyan ms açık/kapalı | ortalama ms | render CPU ms | draw call | üçgen (motor) |
|---|---|---|---|---|---|
| sokak (38 m) | 10,94 / 10,29 (+0,65) | 11,31 / 10,37 | 7,93 / 7,17 (+0,76) | 276 / 247 (+29) | 2,254 M / 2,103 M (+151 bin) |
| mahalle (320 m) | 10,34 / 9,76 (+0,58) | 10,59 / 10,38 | 5,02 / 4,39 (+0,63) | 183 / 154 (+29) | 2,299 M / 2,173 M (+126 bin) |

Yük ağırken (önceki koşular) farklar gürültüye gömüldü (±5 ms, işaret bile değişti); bu yüzden yalnız sakin koşu raporlanır. GPU süresi bu sürücüde 0 döndü (ölçülemedi). Hücre kurulumu: ort. ~2 ms, tek hücre azami 3-29 ms (yükte 130 ms görüldü), kare başı 2 hücre tavanı. Başlangıç kurulumu (`setup_ms`) 0,56-2,3 sn TEK karede (dünya üretimi ~70 sn sürerken; kayıt/yükleme sonrası tekrar yok). Örnek sayıları (menzilde): ~1000 araç, ~1400 insan (profil tavanları 1600/1400).
`SMOKE_OK` (kare ort ≤ 8, P95 ≤ 16,6, üçgen ≤ 900k) bu makinede ÖLÇÜLMEDİ: yaşam kapalıyken bile sokak karesi 10 ms; üçgen sayısı sahne toplamıdır.

## Kalibrasyon (T0 Ismeral, yoğunluk 1,0, 805 km yol)
Dünya toplamı ~17,9 bin araç, ~24,7 bin yaya (hepsi menzilde değil). Sınıf başına 100 m'de medyan araç: ana 1,2 / toplayıcı 2,5 / yerel 2,5; p90: 4,3 / 5,7 / 5,6. Yaya medyan: 1,0 / 3,5 / 3,5. Tavanlar yalnız taşma emniyeti. Tüm oranlar ÇALIŞMA DEĞERİ (`data/view/life.json`); doğru oran AÇIK ürün kararı -> Q-026.

## Doğrulanmamış / AÇIK
Kullanıcı/art-director görsel kabulü; iPad/dokunmatik cihaz davranışı ve süresi; `verify` (quick/full) KOŞULMADI (talimat); `SMOKE_OK` ölçülmedi; kayıt yükleme sonrası lazy yeniden okuma yalnız birim düzeyinde (gerçek kayıtla pencereli koşu yok); araç renk çeşitliliği/tip sayısı; gece/hava görünümü.
