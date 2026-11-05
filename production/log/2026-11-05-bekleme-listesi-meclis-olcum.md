# 2026-11-05 · Bekleme listesi + yıkım -> meclis ÖLÇÜMÜ (qa-engineer; düzeltme DEĞİL)

Soru kaynağı: `2026-11-05-design-director-m2.md` madde 4 ve 5. `src/sim`, `design/foundation`, `blocs.json`, `playable.gd`, `economy_system.gd` DEĞİŞMEDİ. Godot 4.7.2 başsız, `nice -n 19`, `/tmp/imaro-godot.lock` kilidiyle, macOS Intel, makine paylaşımlı. Kurulum gerçek Ismeral (dünya tohumu 1467 ve 2) + `qa_world_support.gd` (oyunun siyaset/ekonomi yapılandırması, yol yetki alanı D2, gerçek kamulaştırma köprüsü). Dal tabanı `183be6d` (main'e ff).

Problar (küçük, kalır): `tools/godot/resettlement_queue_probe.gd` (`RQ_*`), `tools/godot/demolition_council_probe.gd` (`DC_*`). Bulgular: `production/bugs/B-029.md`, `B-030.md`.

## 1. Bekleme listesi çalışıyor mu? ÖLÇÜLDÜ
Politika `policy.set` ile AÇIK. Yol = D2'de kamulaştırmalı, yerinden edilen 56 / 42 / 12 aile (en çok / %90 / medyan; hepsi `unplaced`, D2 `latent` 8686 > `built` ~6910-6954). 200 gün, 3 sim tohumu (3, 7, 11), 9 koşu.
- **İmarsız (yatırımcı yok):** 200 günde şehirde 0 yeni konut; liste 56/42/12'de sabit, 0 aile verildi (`fresh_units_total = 0`, 3 tohum, 9 koşu). Liste yalnız oyuncu imar önerirse beslenir (CAN-03, beklenen).
- **İmarlı** (yola en yakın 4x8 boş parsele `zone.residential`, 0/20/40/60. gün; hepsi `queued`): yatırımcı 36-77 yeni birim bitirdi; ilk ev 69-85. günde; **56/56, 42/42, 12/12 aile listeden ev aldı** (12, 10, 2 `decision.municipal.resettlement_queue` kaydı yazıldı, yazılan = verilen satır sayısı); bekleyen 200. günde 0. Dünya tohumu 2: 72/72, 32/32, 12/12 (ilk ev 69-90. gün).
- **Sınır `max(res_built - latent_hh, 0)`:** her fırsat gününde (yeni ev bitti + bekleyen var; 24 çift, 3 koşu x 3 tohum özdeş) boş birim = **0**; şehir toplamı hep 0. Yine de liste doldu, çünkü varsayılan hane kaderi `return_to_latent` iken aynı bölgeye dönen aile için üst sınır `seekers` (~2000 ev arayan hane) kullanılıyor (`resettlement_queue.gd` `serve` ve `_serve_entry`: `limit = min(fresh, seekers if returns and t == s else vacancy)`). **Design-director hipotezi ŞİMDİKİ VERİDE YANLIŞ; `leave_region` kaderinde DOĞRU:** karşı-olgusal (probe içinde `household_fate = leave_region`, gönderilen veri DEĞİL) aynı koşuda 0 / 56, 0 / 42, 0 / 12 aile verildi, 32 fırsat çiftinin hepsinde boş birim 0 (B-029).
- Gerekçe kaydı: 200. günde günlükte 9 / 5 / 2 kayıt kaldı (12 / 10 / 2 yazıldı), B-027 halka tamponu.

## 2. Yıkım -> meclis oylaması etkisi? ÖLÇÜLDÜ
12 parselli imar (aynı id'ler), 8 sim tohumu x {yeşil, konut}, beklemeler 2/25/90 gün. Kollar: A yol yok, B kamulaştırmalı yol (42 hane), C = B + yol yıkımı (5. gün), D = 6 yol art arda (302 hane). 144 koşu, hata 0, ağ her koşuda taban grafına döndürüldü.
- Meclis üyelerinin güven/kızgınlık/borç (`trust_in_player`, `resentment`, `obligation`) etkeni TÜM kollarda özdeş (üye 1: +15, üye 3: -23, diğerleri 0). `group.reacted` olayı 0.
- Kesim: bloc.2 G 86 -> 87 (B) -> 99 (D) (25. gün); 90. günde 170 -> 173 -> 224, bloc.1 G 0 -> 40 (D). Meclise yansıması `bloc_pressure` -33 -> -35 (90. gün, 5 üye toplamı).
- Gürültüsüz marj yıkımla ARTIYOR: B +3, D +24 üye başına (kaynak: `budget_realism`, D2 yük binde 999 -> 993 / 951). Gürültüsüz tahmin yeşil imar için A/B/C 3-2 KABUL, D 4-1; konut A/B/C 4-1 (B 2. günde 4-0), D 5-0.
- Gerçek oy: yeşil 25 gün A 7 KABUL / 1 RED, B 7/1, C 7/1, D 8/0; yeşil 2 gün A 6/2, B 6/2; yeşil 90 gün A/B/D 8/0; konut 2 ve 25 gün tüm kollar 8/0. RED'ler aynı tohumlarda (oy gürültüsü); yıkım RED sayısını artırmıyor.
- **Sonuç:** ölçülen aralıkta yıkım sonrası halk tepkisi ve güven düşüşü meclis oylamasını bozmuyor, hafifçe kolaylaştırıyor. Tepki -> meclis zincirinin tek bağı `bloc_pressure` (~-2) (B-030).

## Doğrulanmış / varsayılan / test edilmemiş
**ÖLÇÜLEN:** yukarıdaki sayılar (çıktı `RQ_*` / `DC_*` satırları, probe komutları dosya başlıklarında). Tohumlar: liste için 3 sim tohumu (karma sayaçlar özdeş, durum hash'leri farklı: sim tohumu bu sayaçları etkilemiyor, 3 tohum bağımsız kanıt DEĞİL; dünya tohumu 2 ayrı doğruluyor); meclis için 8 sim tohumu.
**VARSAYILAN:** imar paketi "yola en yakın boş parsel, konut, 4x8 parsel" gerçek oyuncu davranışının temsilcisidir; "yıkım" = kamulaştırmalı yol (C kolunda yol yıkımı da); `vote["positions"]` gürültüsüz marj `CouncilEngine.forecast` ile aynı hesap (`draw: 0`) ama probe kendi kopyası; `fresh` ve `vacancy_pre` dışarıdan türetildi (`res_built` farkı + verilen satırlar), `serve` içi hesapla aynı olmayabilir (yalnız sınırın 0 olduğu sonucu için yeterli).
**TEST EDİLMEDİ:** `verify quick/full` (istenmedi); pencereli oyun; D2 dışı bölge; uzun ufuk (>200 gün liste, >90 gün meclis); 12 parsellik plan dışında meclis türleri (örn. 40 birim eşiği); gündem öğesine oyuncu yanıtı (`agenda.respond`); politika kapatıp açma; birden çok bekleyen yol karışımı; UI.
