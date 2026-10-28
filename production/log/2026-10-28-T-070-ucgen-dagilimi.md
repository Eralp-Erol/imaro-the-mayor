# T-070 · Görünür üçgen dağılımı (ADR-0008 ölçümü) · 2026-10-28

Ham veri: `artifacts/library/t062/qa/t070/run2/` (`probe.json`, `probe.log`, `summary_medians.tsv`, `uptime_*.txt`, probe betiği kopyası `t070_run2_probe.gd`). Kod değişmedi; probe repo dışı betiktir (scratchpad, kopyası run2'de). `raw/` altındaki önceki deneme dosyaları KULLANILMADI.

## Koşullar

- Makine: MacBookPro15,1, i7-8850H (12 mantıksal çekirdek), Radeon Pro 560X, `gl_compatibility`, Godot 4.7.2, 1600x900 (800x450 ayrıca), VSync kapalı. **Yük altında ölçüldü** (kullanıcının günlük makinesi): `uptime` başta 4,63 / 4,46 / 4,11, sonda 2,90 / 3,69 / 3,85; koşu içi 1 dk ortalaması 2,7-5,1.
- Tek pencere, tek süreç: toplam pencereli süre 194 s (preset başına: çekirdek 70 s duraklatılmış + 21 s sim'li + 14 s 800x450 küçük pencere; D1 19 s; port 18 s). Çekirdek, 17 ablasyon nedeniyle ~30 s hedefini aştı; toplam 10 dk'nın çok altında.
- Komut: `--demo --veg-block --preset=street:20200,18700`; presetler aynı süreçte `apply_preset` ile geçildi. 3 tur, konfigürasyonlar turlar arasında araya sokuldu; tablo medyan [tur-min..tur-maks]. Tam sahne 240 kare/tur, ablasyon 90 kare/tur (ms'i daha gürültülü, üçgen sayıları deterministik).
- Ablasyon çalışma anında düğüm `visible=false` / `cast_shadow` / `shadow_enabled` ile yapıldı (mevcut `--no-vegetation`, `--hide=` vb. başlatma bayrakları tek oturumda karşılaştırma yapamadığı için); `--veg-lod1=250` ve `--lod0-end` yeniden başlatma gerektirdiğinden yerine `lod0_700` (L0 bitişi 750, L1 başlangıcı 650 m; `--lod0-end=700` eşdeğeri) kullanıldı. Sweep, `--veg-lod1=250` ve `--veg-no-blob` bayrağı ölçülmedi.
- Sim durumu: "tiksiz" = sim duraklatılmış (hiç tick yok); "tikli" ayrı fazda `--demo` hızıyla (900 karenin 161'i = %17,9 tick karesi).
- Headless kare süresi vermez; ms değerleri yalnız pencereli koşudan. Üçgen sayıları render bilgisinden, pencere gerekmeden de alınabilir ama bu oturumda ms ile birlikte alındı.

## Ölçülen: çekirdek `street:20200,18700`, sim duraklatılmış (tiksiz), üçgen kaynağa göre

Görünür = `viewport_get_render_info(VISIBLE)`; "Fark" = tam sahne eksi kalem gizli.

| Kaynak | Üçgen (görünür fark) | Pay (görünür 2,731M) | ms farkı | Not |
|---|---|---|---|---|
| Bina, hero LOD1 yuvası (L0) | 2.091.205 | %76,6 | -3,57 | `bld_nolod0`; ≈ 4.800 örnek (436 üçgen/bina ortalamasından hesap) |
| Bina, PROXY yuvası (L1) | 9.250 | %0,3 | -0,06 | |
| Bina, HLOD1 | 200.884 | %7,4 | -0,74 | |
| Bina, HLOD2 | 19.236 | %0,7 | -0,08 | |
| Bitki, LOD0 | 43.940 | %1,6 | -0,34 | + gölgede aynı 43.940 |
| Bitki, LOD1 | 165.024 | %6,0 | -0,52 | |
| Bitki, leke (blob) | 96.060 | %3,5 | -0,38 | üçgeni gönderilir (fragman atılır) |
| Bitki toplam (`noveg`) | 305.024 | %11,2 | -1,20 | üç kademe toplamı = `noveg` farkı (tam kapanış) |
| Arazi (kara) | 43.575 | %1,6 | -0,94 | üçgen azına rağmen ms büyük (gölgelendirici) |
| Su | 50.072 | %1,8 | -0,21 | |
| Yol | 42.176 | %1,5 | -0,22 | |
| Gölge geçişi (`shadow`) | 132.499 | tam sayaç içinde ayrı | -1,90 (`noshadows`) | bina gölge düşürücü S1 83.464 (%63), bitki L0 43.940 (%33), arazi 5.035 (%4) |
| Canvas (HUD) | 7.800 | | | |

Sayaç toplamı (`RENDER_TOTAL_PRIMITIVES_IN_FRAME`) 2.871.731 = görünür 2.731.432 + gölge 132.499 + canvas 7.800.

Çekirdek tam sahne: görünür 2,731M, sayaç toplamı 2,872M; çizim çağrısı görünür 269 (`noshadows` farkı -51 gölge çizimi ima eder: ≈ 320 toplam, hesap; ADR'nin 353'ü ayrı sayaçtan, burada aynı sayaç alınmadı).

Diğer presetler (tiksiz, medyan): 

| Preset | ort ms | p95 ms | sayaç toplamı | çizim (görünür) | baskın kalem |
|---|---|---|---|---|---|
| `district:D1` | 5,41 [5,40-5,41] | 8,06 [8,0-8,3] | 478.048 | 134 | HLOD1 293.6k (%69 görünür); gölgenin tamamı arazi (45.485); `hide_land` -2,53 ms |
| `street:port` | 5,19 [5,15-5,19] | 7,64 [7,6-7,7] | 316.094 | 117 | bina L0 51.5k, bitki 65.4k, gölge 26.752; `hide_land` -2,41 ms |

## Ölçülen: kare süresi, çekirdek tam sahne (1600x900)

| Durum | ort ms [tur min-maks] | p95 ms [tur min-maks] |
|---|---|---|
| Sim duraklatılmış (tiksiz) | 10,99 [10,96-10,99] | 13,15 [12,8-13,3] |
| Sim çalışıyor, TİKSİZ kareler (739/900) | 10,93 | 13,29 [13,0-13,5] |
| Sim çalışıyor, TİKLİ kareler (161/900) | 12,94 | 19,8 |
| Sim çalışıyor, tüm kareler | 11,20 [11,12-11,30] | 13,82 [13,4-14,4] |
| Çekirdek, bitkisiz, duraklatılmış | 9,79 | 11,86 |
| 800x450, tam / bitkisiz / L0 kapalı | 9,76 / 8,62 / 4,91 | 11,68 / 10,41 / 6,45 |

Dikkat: tur-min/maks yayılımı bu oturumda çok dar (≤0,3 ms ort); ADR'nin ±%40 yük gürültüsü bu oturumda görülmedi, ama yük 3-5 idi ve oturum tek 3 dakikaydı; başka zamanda tekrar edilirse kayabilir.

## Eşiklere göre durum (ikisi de gösterilir; seçim yapılmadı)

| Ölçüt (çekirdek) | Ölçülen | (a) Katı ADR-0008 | (b) Yumuşatılmış çalışma eşiği |
|---|---|---|---|
| Ort ms | 10,99 duraklatılmış; 11,20 sim'li tüm kareler | ≤ 8,0 -> **GEÇMEZ** | ≤ 14 -> geçer |
| p95 ms, tiksiz | 13,15 duraklatılmış; 13,29 sim'li tiksiz | ≤ 16,6 -> geçer | ≤ 20 -> geçer |
| p95 ms, tüm kareler (sim'li) | 13,82 (tikli kare p95 19,8) | birleşik kapı (T-074) 16,6 -> geçer bu oturumda | (eşik tanımlı değil) |
| Üçgen (sayaç toplamı) | 2,872M | ≤ 900k -> **GEÇMEZ** (3,2x) | (eşik tanımlı değil) |
| Çizim çağrısı | 269 görünür, ≈ 320 gölge dahil (hesap) | ≤ 400 -> geçer | (eşik tanımlı değil) |
| `district:D1` / `street:port` | 5,41 / 5,19 ms, p95 8,06 / 7,64, 478k / 316k | hepsi geçer | geçer |

Referans noktalar (ölçüm, öneri değil): L0 yuvası gizlenince çekirdek 7,42 ms, p95 9,75, sayaç 780.526 (katı ADR ölçütlerinin dördü de geçer); `lod0_700` ile 8,91 ms, p95 11,0, sayaç 2.036.805 (görünür -834.926, %30,6).

## Hesaplanan

- Bina toplamı (L0+L1+HLOD1+HLOD2) 2.320.575 ≈ `bld_all` farkı 2.308.103 (%0,5 içinde). Kalem toplamı: bina 2.308k + bitki 305k + kara 43,6k + su 50,1k + yol 42,2k = 2.749k, ölçülen görünür 2.731k ile %0,6 fark; ±%10 kapanış ölçütü sağlandı.
- ms/üçgen kaynağa göre çok farklı: L0 ≈ 1,7 ms/M, HLOD1 ≈ 3,7, bitki ≈ 3,9 (+41 çizim çağrısı), gölge geçişi ≈ 14 ms/M, kara 21 ms/M. ADR K-2'nin tek doğrusu (2,78 ms/M) kaynak bağımsız değil; üçgen düşürmenin ms'e etkisi kaleme bağlı. ms toplamı da toplanmıyor (bina kalemleri -4,45, `bld_all` -5,11).
- 800x450'de ms yalnız ~%11 düştü (10,99 -> 9,76) ve 4 kat az pikselde bile çekirdek 8 ms'in üstünde: sahne ağırlıklı geometri/CPU-GL bağımlı, fragman duyarlılığı düşük (ADR R1 çekirdekte ağırlıklı çıkmadı). `district`/`port`'ta ise kara gizlenince -2,4...-2,5 ms: oralarda arazi gölgelendirici/fragman maliyeti belirgin.

## `viewport_get_render_info` / sayaç gölgeyi içeriyor mu

**Doğrulandı (ampirik).** 117 koşunun hepsinde `RENDER_TOTAL_PRIMITIVES_IN_FRAME` = VISIBLE + SHADOW + CANVAS (en büyük sapma 0); `noshadows` ablasyonunda SHADOW 0'a ve sayaç tam gölge payı kadar düşer (2.871.731 -> 2.732.996). Not: gölge geçişinin çizim çağrısı SHADOW türünde hep 0 raporlanıyor (çizim sayısı gölgeyi içermiyor ya da raporlanmıyor); gölge çizim çağrısı yalnız `noshadows` farkından kestirildi.

## ADR-0008 kök neden tahmini

- "En büyük kalem hero LOD1 (L0) yuvasıdır": **DOĞRULANDI.** 2,091M = görünürün %76,6'sı, tüm sayacın %72,8'i; ms'te de en büyük (-3,57).
- "Neden 1 km hücre MERKEZİ LOD'dur": **kısmen / doğrudan DOĞRULANAMADI.** L0 yuvasının baskınlığı ölçüldü, ama mekanizmayı (merkez ölçümü yüzünden 1,5-2,2 km'deki binaların L0 çizilmesi) ayıracak örnek-başına-uzaklık ölçümü yok; bu kod/probe değişikliği ister. Dolaylı: hücre-merkezli kısaltma `lod0_700` yalnız -%30,6 görünür üçgen ve 8,91 ms verdi (hâlâ katı eşiğin üstü, 2,04M); yani yalnız eşik kısaltmak çekirdeği katı ölçüte getirmez (ADR K-4 ret koşulu: ölçümle doğrulandı). ADR'nin örnek-başına halka tahmini (ΔP ≈ -0,71·X ≈ -1,48M) **ölçülmedi**.
- "Bitki T-062 artışının tamamı": bitki 305k (%11,2), 1,2 ms; bina dışı ikinci kalem. HLOD1 200k, gölge 132k (1,9 ms).
- Yeniden açma koşulu "bina dışı kalem baskın çıkarsa": çıkmadı (bina %84,5).

## Ölçülemeyen / eksik

- Örnek-başına gerçek uzaklık dağılımı (halka kazancı) ve sweep ölçümü; `--veg-lod1=250` (üst sınır: LOD1 toplamı 165k, 0,52 ms); `veg_nop` (P kademesi; üç kademe toplamı `noveg` ile kapandığı için ≈ 0); GPU süresi (Compatibility'de yok); iPad.
- Gölge geçişinin çizim çağrısı sayısı doğrudan alınamadı. Performance çizim çağrısı sayacı bu oturumda okunmadı (ADR'nin 353'ü ile doğrudan karşılaştırılamaz).
- Süreç notu: önceki denemenin `run_matrix.sh` ve Godot süreçleri (PID 64137/66952/66953) yarıda kesilmiş değil, arka planda çalışmaya devam ediyordu (ppid 1); başkasının PID'i olduğu için öldürülmedi, 22:29'da kendiliğinden bitmesi beklendi, sonra tek Godot ile bu ölçüm alındı. `raw/` altındaki o koşunun çıktıları kullanılmadı.
