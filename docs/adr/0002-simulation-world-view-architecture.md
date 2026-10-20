# ADR-0002 · Simülasyon, dünya verisi ve görünüm mimarisi

- Durum: kabul · Tarih: 2026-10-20 · Karar veren: technical-director (studio bootstrap)
- Karşıladığı gereksinimler: TEK-01, TEK-02, TEK-03, WLD-01, WLD-09, WLD-11, CAN-03, CAN-11, SIM-01..12, CAN-09

## Bağlam
Foundation tek fiziksel dünyayı (ülke → metropol → ilçe → sokak → insan), otonom aktörleri, görünür ve sorgulanabilir nedenselliği, oyuncu bakmıyorken evrilen ilçeleri ve makam değişiminde sıfırlanmayan dünyayı istiyor. Silinen eski POC (32 parsel, tek mahalle) bu ölçeği taşımıyordu (F06, D-001). Kesin ekonomik formüller, zaman oranları, ilçe sınırları AÇIK/ÇM.

## Karar
1. **Katmanlar ve bağımlılık yönü** (yalnızca aşağı doğru):
   - `src/sim/` — saf model: `GameState`, sistemler (hane, işletme/yatırımcı, belediye bütçesi, altyapı kapasitesi, siyaset/çıkar grupları, makro), komutlar, RNG akışları, kayıt. Godot Node/render/input bağımlılığı yok (`.claude/rules/simulation.md`).
   - `src/world/` — tek dünya verisi: yükseklik alanı, kıyı/su, bölge çapaları (D1–D6 çalışma kodları), ağlar (yol, ray, feribot), bloklar/parseller; tohumlu deterministik üreteçler + elle düzenlenebilir kontrol verisi (`data/world/`). Simülasyon bu veriyi sahiplenir ve değiştirir (yeni yol, parsel bölünmesi).
   - `src/view/` — Godot düğümleri: chunk'lı arazi, MultiMesh bina örnekleme, görünürlük aralıklı HLOD, kamera, seçim/picking, inşaat görselleri. Sim'den yalnızca snapshot/olay okur; oyuncu niyetini **komut** olarak gönderir.
   - `src/ui/` — HUD ve paneller; yalnızca sim verisi ve sim'in kaydettiği gerekçeler.
   - `src/app/` — önyükleme, tick sürücüsü (gerçek zaman × hız → tamsayı tick), kayıt yuvaları, sahne geçişleri.
2. **Tek koordinat sistemi:** metre cinsinden tek dünya; kalıcı veri GDScript `float` (64-bit) / tamsayı. Render transformları 32-bit olduğundan görünüm katmanı **origin rebasing** uygular (kamera odağına göre). Ülke ölçeği aynı yükseklik verisinin kaba LOD'udur; Ismeral bu verinin içinde yüksek çözünürlüklü bölgedir. Ayrı "ülke haritası" çizilmez (WLD-01). Anderva–Ismeral ölçek oranı veri parametresidir (AÇIK).
3. **Simülasyon LOD'u:** oynanan ilçe ve yakın çevresi parsel/bina düzeyinde açık modellenir; diğer Ismeral bölgeleri hücre/kohort düzeyinde toplu modellenir ama **tick'lenir** (WLD-11); diğer altı metropol makro düzeyde soyuttur (SIM-06). Odak değişince ayrıntı düzeyi veriden yükseltilir/indirgenir; geçmiş korunur (WLD-09, CAN-11).
4. **Zaman:** temel tick = 1 oyun günü; aylık/çeyreklik sistemler (bütçe, meclis, seçim gündemi) zamanlayıcıyla aynı tick döngüsünde, sabit sırayla. Oranlar ÇM; config'te.
5. **Determinizm:** sistem başına tohumlu RNG akışı; tamsayı para; sıralı iterasyon; komut günlüğü. Kayıt = sürümlü durum serileştirmesi + RNG durumları + tick sayacı; test: kaydet→yükle→N tick hash eşitliği.
6. **Ölçek için veri yönelimli çekirdek:** büyük popülasyonlar Packed*Array sütunlarında (id ile), küçük ve zengin varlıklar (yatırımcı profilleri, meclis) RefCounted sınıflar. GDScript'te kalınır; profiler kanıtıyla sıcak yollar `godot-cpp` GDExtension'a taşınabilir (iOS'ta Rust/gdext deneysel → tercih edilmez).
7. **Nedensellik kaydı:** her aktör kararı `{aktör, karar, faktörler, eşik}` gerekçesi üretir; UI ve testler bunu okur (SIM-12).
8. **Kampanya izolasyonu:** kayıt kampanya kimliğiyle ayrılır; bölgeler arası karakter taşınmaz (CAN-09).

## Alternatifler
| Seçenek | Neden değil |
|---|---|
| Tam ajan tabanlı (her vatandaş ayrı) | Metro ölçeğinde maliyetli, foundation gerektirmiyor ("gözlemlenebilir nedensellik kadar"). Görünür ölçekte ayrıntı yeterli. |
| ECS framework / eklenti | Foundation ve önceki brif aşırı altyapıyı reddediyor; Godot'ta olgun deterministik ECS yok. Packed sütunlar aynı veri yerelliğini verir. |
| Her zoom için ayrı sahne/harita | WLD-01'i doğrudan ihlal eder. |
| Double-precision Godot derlemesi | Özel derleme + iOS belirsizliği; 40 km'lik metroda origin rebasing yeterli. Ülke ölçeğinde gerekirse yeniden değerlendirilir. |

## Sonuçlar ve riskler
- Toplu (kohort) ilçe modeli ile açık parsel modeli arasındaki geçiş tutarlılığı en zor teknik risk; M1'de küçük ölçekte test edilmeli.
- GDScript tick maliyeti ölçekte risk; bütçe ve ölçüm `experiments/scale-bench/RESULTS.md` ve ADR-0001'de.
- Yeniden açma tetikleyicisi: hedef cihazda tick bütçesi aşımı, kayıt boyutu/geçiş tutarsızlığı, kullanıcının ölçek/kapsam kararları (Q-002).
