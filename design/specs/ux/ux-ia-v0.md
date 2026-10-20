# UX bilgi mimarisi v0 (T-018)

Statü: ÇALIŞMA MODELİ / ÖNERİ. Hiçbir yerleşim, kısayol, ad veya görsel kimlik kanon değildir. F05-D'de AÇIK olanlar (HUD, açılış menüsü, istatistik tabloları, kamera/UX akışı) burada yalnız **seçenek + öneri + AÇIK SORU** olarak geçer (§8).
REQ: SIM-09, SIM-12, TEK-04, PLT-02, PLT-05, CAN-03..06, CAN-10, VIS-07. Yoldaş belgeler: `ux-flows-v0.md`, `ux-layout-v0.md`, `ux-data-needs.md`, `ux-text-system.md`, `ux-states-a11y-v0.md`, `data/ui/strings.tr.json`.
Girdi kaynakları: F01/F03 (üç mod, kesintisiz city-building akışı, "uzun planlama seanslarını siyasi pop-up'larla kesme"), F02 alt ölçek sözleşmesi, ADR-0004 (profiller), `politics-elections.md` (sicil, meclis, seçim). Konsept görsellerdeki hiçbir UI, sayı, etiket kullanılmadı (VIS-07).

## 1. Oyuncunun zihinsel modeli
Oyuncu **bir belediye başkanıdır**; şehri doğrudan "yaratmaz", **koşulları kurar**: kamusal alanı çizer, arazi kullanımı önerir, parayı ve önceliği yönetir, meclis ve gruplarla pazarlık eder. Sonra **dünyanın cevap verdiğini izler** ve nedenini sorar.

Döngü (F03): *karar → özel aktörlerin tepkisi → fiziksel değişim → etki → siyasi geri bildirim*. UX'in üç görevi:
1. **Eylemi ucuz ve doğrudan hissettirmek** (harita üzerinde çizim, sürükle, onayla; modal sorgu yağmuru yok).
2. **Cevabı dünyada göstermek** (inşaat, protesto, boş parsel) ve panelde okunur kılmak.
3. **Nedeni her zaman bir tık/dokunuş uzakta tutmak** (SIM-12): her bildirim/olay/sonuçta "Neden?" eylemi.

Anlatım ilkesi: dünya birincil, panel ikincil. Paneller şehri gömmez (bkz. §3 yüzey bütçesi).

## 2. Yüzey hiyerarşisi
Altı katman, üstten alta öncelik (üst katman girdiyi önce alır; "UI girdiyi kamera/dünyadan önce tüketir", ui.md):

| Kat | Yüzey | Süre / kalıcılık | Örnek | Dünyayı örter mi? |
|---|---|---|---|---|
| L0 | **Ana görünüm** (3D dünya + dünya içi işaretler: seçim halkası, çizim önizlemesi, protesto/inşaat ikonları) | her zaman | şehir, imar önizleme boyası | — |
| L1 | **HUD çerçevesi** (kalıcı, ince): üst şerit (zaman kontrolü, tarih, para, ölçek göstergesi), mod/araç çubuğu, mini bildirim şeridi | her zaman | duraklat/1×/2×/3×, mod sekmeleri | Kenarlarda; merkez serbest |
| L2 | **Bağlamsal panel** (bir tane yan panel): denetçi, nedensellik, bütçe, sicil | seçim/komutla açılır, kapatılabilir/sabitlenebilir | parsel denetçisi | Yan şerit; sabit genişlik |
| L3 | **Araç içi yüzey** (çizim sırasında alt/üst onay çubuğu, maliyet, uyarı) | araç etkinken | yol çizimi "Bitir/İptal" | Küçük şerit |
| L4 | **Modal akış** (yalnız geri alınamaz/bağlayıcı kararlar ve oylama sonucu) | kısa, odaklı | meclise sun onayı, seçim gecesi | Evet (kısmi) |
| L5 | **Sistem** (duraklatma menüsü, ayarlar, hata diyaloğu) | istek üzerine | ayarlar | Evet |

Kurallar:
- **Aynı anda en fazla bir L2 paneli** açıktır (desktop'ta isteğe bağlı ikinci "sabit" panel — AÇIK SORU 3).
- Simülasyon olayları (protesto, yatırımcı vazgeçti) **L1 bildirim şeridine** düşer, **asla modal açmaz** (F03 "kesintisiz akış"). Modal yalnız oyuncunun başlattığı bağlayıcı eylemler ve seçim sonucu içindir.
- Panel açıkken harita kaydırma/zoom çalışmaya devam eder (panel dışı alan haritadır).
- Hiçbir yüzey kurulmamış bir sistemi **boş sekme olarak** göstermez; ya gizlenir ya `state.not_built` ile dürüstçe etiketlenir (ui.md).

## 3. Yüzey bütçesi (şehri gömmeme)
Ekranın alanı oranı hedefi (referans 1920×1080 ve iPad Pro 11" yatay, bkz. `ux-layout-v0.md`):
- Kalıcı HUD (L1) en çok ekran alanının ~%12'si; açık L2 paneli en çok genişliğin ~%28'i (masaüstü) / ~%38'i (iPad yatay) / alt sayfa yüksekliğin ~%45'i (iPad dikey).
- Panel açıkken harita merkezinin en az yarısı görünür kalır. Bu **doğrulanabilir bir kabul ölçütü** olarak T-019'a taşınır (ekran görüntüsü ölçümü).

## 4. Üç etkileşim modu (F03) ve geçiş
Mod, **araç takımı bağlamıdır**, ekran değiştirmez; dünya aynı kalır. Üç mod sekmesi L1 araç çubuğunda daima görünür:

| Mod | Anahtar | Araç çubuğu | L2 panel varsayılanı | CAN |
|---|---|---|---|---|
| **İnşa** (`mode.build`) | doğrudan belediye inşası | Yol, Bulvar, Kavşak, Meydan, Park, Belediye tesisi, Kamusal yapıyı kaldır | Yol/kamu alanı özellikleri (sınıf, maliyet) | CAN-04 |
| **İmar** (`mode.plan`) | planlama/imar | İmar önerisi (çokgen/parsel boyama), Katman, Denetçi | İmar önerisi formu | CAN-05 |
| **Yönetim** (`mode.manage`) | siyaset/ekonomi | Bütçe, Öncelik, Meclis, Sicil/Seçim | Seçili yönetim sayfası | CAN-06 |

Geçiş kuralları:
1. Mod değiştirmek **yarım komutu iptal etmez**: devam eden çizim taslağı korunur ve L3'te "taslak bekliyor" gösterilir; oyuncu onaylar ya da `Vazgeç` der.
2. **Denetçi** ve **Neden?** her modda erişilir (mod bağımsız okuma araçları).
3. Zaman akışı mod değişiminden etkilenmez (planlama sırasında oyun duraklatılabilir; otomatik duraklatma yok, yalnız ayar olarak sunulur — AÇIK SORU 6).
4. Mod önerisi sinyali: yönetim mod rozeti (örn. bekleyen oylama) **sayı+metin** gösterir, kırmızı nokta tek başına değil (erişilebilirlik).
5. "Özel bina yerleştir" aracı **hiçbir modda yoktur** (CAN-03). İnşa modunda yalnız kamusal/belediye yapıları; imarda yalnız koşul önerisi. UI metni bunu açıklar: `draw.no_private_building`, `zoning.no_instant_building`.

## 5. Zoom ölçeği ile UI ilişkisi
Ölçekler F02 alt ölçek sözleşmesinden: **Ülke → Metropol → İlçe → Mahalle/Parsel → Sokak/insan**. Tek dünya; zoom bir mod değil, **ayrıntı seviyesi**dir. Kamera davranışı (T-003) bu UX'e ölçek olayı verir; UX kamerayı sürmez.

| Ölçek | Dünyada görünen | UI davranışı | Kullanılabilir araçlar | Okuma yüzeyi |
|---|---|---|---|---|
| Ülke | 7 metropol bölgesi | HUD sade; ilçe/parsel bilgisi kapalı | Yönetim (ulusal bağlam), harita katmanı | Metropol/özet satırları |
| Metropol | altı çalışma bölgesi (D1..D6) | bölge etiketleri (`district.code`), hover/seçimde bölge kartı | Yönetim, bölgeler arası projeler (yetki varsa), katman | Bölge kartı, bütçe |
| İlçe | mahalleler, ana yollar | yol/imar önizlemesi çizilebilir | İnşa (yol, bulvar, meydan), İmar (çokgen), Yönetim | Denetçi (ilçe) |
| Mahalle/Parsel | parseller, bloklar, binalar | parsel sınırları + denetçi, imar boyası | Tüm araçlar; hassas düzenleme | Denetçi (parsel), Neden? |
| Sokak/insan | cepheler, kaldırım, araçlar | ince ayar, yaya/yol kesiti; HUD en sade | Kavşak/kesit ayarı, yerel inceleme | Denetçi, dünya içi olay ikonları |

Kurallar:
- **Ölçek kapıları dürüsttür**: bir araç o ölçekte anlamsızsa gizlenmez gri bırakılmaz, tıklanınca `zoom.locked_here` açıklaması çıkar ("X için İlçe ölçeğine yakınlaşın") ve tek dokunuşla yakınlaştırma önerir. Ölü buton yok.
- Etiket yoğunluğu ölçekle azalır/artar (LOD'lu UI): ülke ölçeğinde yalnız bölge adları, sokakta yalnız seçili nesne.
- Dünya içi olay ikonları (protesto, inşaat durdu, yatırımcı vazgeçti) **ölçekle toplulaşır**: uzaktan sayılı küme, yakından tekil ikon; tıklayınca ilgili `ReasonRecord`.
- Ölçek göstergesi (ölçek adı, `zoom.*`) üst şeritte okunur; ölçek **okları/çubukları konsept görselinden kopyalanmaz** (VIS-07).
- Zoom geçişleri sırasında açık L2 paneli seçili nesneye bağlı kalır; nesne ölçekte görünmez olsa da panel kapanmaz ("Haritada göster" ile dönülür).

## 6. Sayfa/akış haritası (özet)
```
Açılış (AÇIK §8) → Yükleme → Ana görünüm
Ana görünüm ─ L1: Zaman | Para | Ölçek | Mod sekmeleri | Bildirim şeridi
   ├─ İnşa: yol/kamusal alan çizimi (L3) ─ onay → komut → kuyruk
   ├─ İmar: imar önerisi (L2 form) ─ meclis gerekiyorsa → Meclis oylaması (L2)
   ├─ Yönetim: Bütçe (L2) · Meclis (L2) · Sicil/Seçim (L2)
   ├─ Denetçi (L2): parsel / ilçe ── "Neden?" ──▶ Nedensellik paneli (L2)
   └─ Bildirim ── "Nedenini gör" ──▶ Nedensellik paneli
Sistem (L5): Duraklatma menüsü · Ayarlar · Kaydet/Yükle
```
Her akışın adım adım fare/klavye/trackpad + dokunmatik karşılığı: `ux-flows-v0.md`.

## 7. Girdi profili ilkeleri (ADR-0004, PLT-05)
- **Aynı oyuncu fiilleri**, farklı yerleşim. Fiiller: *Seç, Çiz, Onayla, Vazgeç, Geri al, Zoom, Kaydır, Döndür, Bağlam menüsü, Neden?, Duraklat/Hız*.
- **Masaüstü (birincil):** hover bilgisi (denetçi önizleme baloncuğu), sağ tık bağlam, tekerlek zoom, klavye kısayolları, daha yoğun paneller, çok-sütunlu tablolar.
- **Dokunmatik (ikincil, ilk günden):** hover YOK; her hover bilgisi **seç → denetçi** ile erişilir; ≥44 pt hedefler; kısayol yerine görünür düğme; uzun basış = bağlam menüsü; çizimde nokta-ekle + onay çubuğu (sürükle-pan ile çakışmaz).
- **Profil seçimi:** `platform_profile` (T-007) verir; kullanıcı `settings.input_profile` ile değiştirebilir. Sim kodu profili okumaz.
- Hiçbir fiil yalnız tek profilde bulunmaz (PLT-03: masaüstü kapsamı iPad için azaltılmaz — iPad'de panel *yerleşimi* farklıdır, *işlev* eksik değildir).

## 8. Görsel/etkileşim dili — SEÇENEKLER ve ÖNERİ (kanonlaştırılmaz)
art-director ile çakışma noktaları **işaretlidir (art-dir)**; tek bir görsel kimlik seçilmedi.

### 8.1 HUD stili (F05-D AÇIK)
| Seçenek | Tanım | Artı | Eksi |
|---|---|---|---|
| A. İnce çerçeve | üstte ince şerit, altta araç çubuğu, sağda tek panel | dünya geniş, iki profile kolay | bilgi yoğunluğu panelde |
| B. Yan ray | solda dikey araç rayı, sağda panel | masaüstü geniş ekranda verimli | iPad dikeyde dar |
| C. Dünyaya gömülü (diegetic) | bilgiler masa/harita nesneleri, bina üstü etiket | atmosfer güçlü | okunabilirlik/erişilebilirlik riski, dokunmatik hedefler (art-dir) |
**Öneri:** A'yı ortak iskelet olarak uygula; görsel kaplama (tema) art-director'un kararına kadar tarafsız tutulur ve tema dosyasından değişir. **AÇIK SORU 1.**

### 8.2 Açılış menüsü (F05-D AÇIK)
| Seçenek | Tanım |
|---|---|
| A. Minimal | Devam / Yeni / Yükle / Ayarlar / Çık, arkada canlı şehir kesiti |
| B. Senaryo seçimli | Yeni oyunda başlangıç ilçesi (D-002: oyuncu seçer) + başlangıç modu seçimi (`start_mode` AÇIK) |
| C. Doğrudan oyun | Son oturuma düşer, menü duraklatma menüsüdür |
**Öneri:** B'nin iskeleti veriyle (ilçe listesi `WorldData`'dan, başlangıç modu seçenekleri yapılandırmadan), görsel olarak A. Başlangıç modu seçimini **kanonlaştırmadan** (kampanya/göreve gelmiş/ikisi) yapılandırılabilir bırak. **AÇIK SORU 2.**

### 8.3 İstatistik tabloları (F05-D AÇIK)
| Seçenek | Tanım |
|---|---|
| A. Harita katmanları | kesim bazlı ısı/işaret katmanları, ayrıntı denetçide |
| B. Tablo + zaman serisi paneli | yönetim modunda sütunlu tablolar, küçük grafikler |
| C. Karma | katman + tablo; tablo satırı harita konumuna bağlı |
**Öneri:** C; her sayı bir `ReasonRecord`'a ya da sim alanına bağlanır ("Neden?" tıklanabilir). Tek toplam skor yok (SIM-09). **AÇIK SORU 4.**

### 8.4 Kamera/UX akışı (F05-D AÇIK)
Kamera kontrol şeması (masaüstü: sürükle-pan, tekerlek zoom, Q/E dönüş; dokunmatik: tek parmak pan, pinch zoom, iki parmak dönüş — ADR-0004 §Karar 2) bu spec'in varsayımıdır; nihai şema T-003. Zoom adımlarının "yakınlaşırken şehir akışı" mı yoksa ölçek kapısı mı olduğu AÇIK. **AÇIK SORU 5.**

## 9. Açık sorular (koordinatör QUESTIONS.md'ye gruplar)
1. HUD stili ve görsel kaplama: A/B/C? (art-director + kullanıcı)
2. Açılış menüsü biçimi ve başlangıç modu (aday olmak / göreve gelmek / ikisi).
3. Aynı anda iki sabit panel (masaüstü) gerekli mi, yoksa tek panel mi?
4. İstatistik tablosu biçimi ve hangi göstergelerin ilk sürümde sunulacağı.
5. Zoom: sürekli akış mı, ölçek kapıları mı; araç kapıları ne kadar sıkı?
6. Planlama sırasında otomatik duraklatma varsayılanı (açık/kapalı)?
7. Oyun içi takvim/saat biçimi (ay adı var mı, gün/yıl mı?). Şimdilik `clock.date_ingame` yer tutucu.
8. Para birimi (Q-003) — UI yalnız yapılandırmadan okur; karar gelince yapılandırma değişir, metin değişmez.
