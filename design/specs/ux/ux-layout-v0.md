# Düzen spec'i v0: masaüstü + iPad (T-018 ölçüt 3)

Statü: ÇALIŞMA MODELİ / ÖNERİ. Ölçüler Godot mantıksal birimidir (stretch ayarı `project.godot` — koordinatör — şu an tanımsız; öneri: `canvas_items` + `expand`, taban 1920×1080; ADR-0001 Compatibility ile uyumlu, ek renderer özelliği gerekmez). 1 mantıksal birim ≈ 1 pt kabul edilir; ölçek `settings.ui_scale` ile çarpılır. Doğrulama: T-019/T-008 (gerçek cihaz yok → "çalışır" denmez, TEK-04).

## 1. Profil seçimi ve ölçek
| Profil | Ne zaman | Taban ölçek | Hover |
|---|---|---|---|
| `desktop` | Windows/macOS | 1.0 | var |
| `touch` | iPadOS (ya da kullanıcı zorlar) | 1.15 (öneri; metin ≥ 17 pt) | **yok** |
Profil `platform_profile`'dan okunur (T-007); UI sim'e profil bildirmez. Aynı sahneler, profil başına **tema sabitleri** (`touch_min_target`, `padding`, `body_size`) ve **düzen değişkeni** (yan panel ↔ alt sayfa) değişir; iki ayrı UI yazılmaz.

## 2. Masaüstü
| Pencere | Davranış |
|---|---|
| Minimum 1280×720 | L2 panel genişliği 360; üst şerit tek satır; araç çubuğu sade (kısa etiketler) |
| 1920×1080 (referans) | L2 panel 400 sağda; araç çubuğu altta ortada, etiketli |
| 2560×1440 ve üzeri / ultra geniş | paneller **büyümez**, sabit genişlik; fazla alan haritaya gider; UI ölçeği ayarla artar |
| Pencere boyutlandırma | çapalar + `Container`; tek boyuta kilitli konum yok |

Yerleşim (öneri A, bkz. ux-ia §8.1):
```
┌ üst şerit: [Duraklat 1× 2× 3×] [Tarih] │ [Para] │ [Ölçek] ............. [Ayarlar] ┐
│ [sol-üst: bildirim şeridi, kısa, 3 öğe] [gündem rozeti: sayı+süre]  [sağ: L2 panel] │
│                                                                                  │
│                          DÜNYA (merkez serbest)                                  │
│                                                                                  │
└ alt-orta: [İnşa | İmar | Yönetim] + seçili modun araçları        [mini bilgi] ┘
```
- Hover önizleme baloncuğu: 3 satır, imleçle 12 px ofset, ekran dışına taşarsa çevrilir.
- Klavye: tüm L1/L2 kontrolleri Tab ile gezilir, odak halkası görünür; kısayol listesi `settings` altında gösterilir ve **yeniden atanabilir** (veri dosyası, T-019).
- Trackpad (macOS): iki parmak kaydır = pan, pinch = zoom, iki parmak döndür = döndür (ADR-0004).
- Çok monitör/HiDPI: UI `content_scale` ile; metin vektör fonttan, bulanık bitmap yok.

## 3. iPad (dokunmatik)
Referans cihaz: iPad Pro (D-004). Mantıksal boyutlar (11": 1194×834 yatay, 834×1194 dikey; 13": 1376×1032 / 1032×1376 — **cihaz çözünürlüğü sabit gömülmez, çalışma zamanında okunur**).

### 3.1 Güvenli alan
- `DisplayServer.get_display_safe_area()` (Rect2i, piksel) ve pencere boyutundan hesaplanan **`SafeAreaMargin` konteyneri** tüm L1/L2 köklerini sarar. Hesap `NOTIFICATION_WM_SIZE_CHANGED` ve yön değişiminde yeniden yapılır.
- Ev göstergesi (alt), durum çubuğu (üst) ve yuvarlak köşeler için **ek iç boşluk 8 pt**. Kritik düğmeler güvenli alan dışına çizilmez; yalnız dünya render'ı kenara kadar uzanır.
- Hiçbir kritik düğme ekran kenarına ≤ 16 pt bitişik değildir (sistem kenar jestleriyle çakışma).

### 3.2 Hedefler ve el erişimi
- **Her etkileşimli kontrol ≥ 44×44 pt** (görsel daha küçük olsa da hit alanı bu kadar), komşu hedefler arası ≥ 8 pt. Sık fiiller (Onayla, Vazgeç, Duraklat, Mod sekmeleri) ≥ 56 pt.
- **Başparmak bölgeleri** (iki elle tutuş, yatay): sık kullanılan eylemler (araç çubuğu, onay çubuğu, zaman kontrolü) alt-sol ve alt-sağ köşelere yakın; L2 panel sağda. Seyrek eylemler (ayarlar) üst köşede.
- Simge-tek düğme yok: etiket her zaman görünür ya da uzun-bas ipucu *ek* olarak (tek erişim değil).
- Kaydırıcılar 44 pt tutamak; alternatif +/− adımlayıcı.
- Metin: gövde ≥ 17 pt, yardımcı ≥ 13 pt.
- Hover yok: hover'a bağlı hiçbir bilgi yok; "seç → denetçi".

### 3.3 Yön / döndürme
| Yön | Düzen |
|---|---|
| Yatay (varsayılan, oyun için önerilen) | masaüstüne yakın: üst şerit, alt araç çubuğu, **sağda L2 yan panel** (en çok %38 genişlik) |
| Dikey | L2 panel **alt sayfa** (en çok %45 yükseklik, sürüklenebilir tutamak + kapat); araç çubuğu iki satıra bölünebilir; üst şerit aynı |
- Döndürme sırasında: açık panel, seçim, çizim taslağı ve zaman durumu **korunur**; yeniden yerleşim animasyonsuz ya da kısa (hareket azaltma açıksa anlık).
- Sim yönden etkilenmez (platform bağımsız sonuç, PLT-04).
- Her iki yön de desteklenir (PLT-02). Dikey yönde kamera çerçevesi T-003/T-008'e bırakılır.

### 3.4 Dokunmatik jestler (kamera ve UI sözleşmesi)
UI kontrolleri olayı önce tüketir; kalanı kameraya gider. Jest tablosu: tek parmak sürükle = pan; pinch = zoom; iki parmak dönüş = döndür; uzun bas = bağlam; çift dokunma = hedef ölçeğe yakınlaş (opsiyonel). Çizim aracı etkinken tek parmak sürükle yine **pan**'dır (çizim noktaları dokunarak eklenir). Çok dokunuşta her parmak `index` ile izlenir; uygulama odak kaybında jestler iptal edilir. Eşikler (tap slop 24 vb.) ui_scale ile ölçeklenir, T-019'da sabitlenir.

## 4. Kalıcı HUD içeriği ve veri kaynağı (yalnız gerçek sim verisi)
| Öğe | Kaynak | Boş/yok ise |
|---|---|---|
| Zaman kontrolü, tarih | `ClockView` | öğe gizli (MOCK modunda "MOCK" rozeti) |
| Para (bakiye) | `BudgetView.balance` + yapılandırma `¤` | gizli |
| Ölçek göstergesi | kamera ölçek olayı (UI/view; sim değil) | — |
| Bildirim şeridi | `SimEvent` akışı | boş (öğe yok) |
| Gündem rozeti (modal değil; tıklayınca L2 Gündem paneli) | `AgendaItemView` listesi (v1.1 TEKNİK istek; sayı + en yakın `deadline_tick`) | gizli (`agenda.not_built` yalnız Yönetim içinde) |
| Nüfus, memnuniyet, "puan" | **HUD'da kalıcı olarak YOK**; nüfus gibi gerçek bir sayı ancak sim `DistrictView.population` verirse denetçide |
Tek "Mutluluk %" hiçbir yerde yoktur (SIM-09).
**MOCK kuralı:** `MockSimFacade` ile çalışırken (ui_lab, T-019) ekranın sabit bir köşesinde `app.mock_banner` ve her mock sayıda `app.mock_badge` görünür; gerçek facade bağlanınca rozetler kodla değil **facade bayrağıyla** (`SimFacade.is_mock()`) kaybolur. Ekran görüntülerinde MOCK etiketi kalmalıdır.

## 5. Panel boyutları özeti
| | Masaüstü 1920×1080 | iPad yatay | iPad dikey |
|---|---|---|---|
| L2 | sağ 400 (maks %28) | sağ ≤ %38 | alt sayfa ≤ %45 |
| L1 üst şerit | 48 | 56 (güvenli alan altında) | 56 |
| Araç çubuğu | 56, altta ortada | 64, alt | 64×2 satır |
| Min hedef | 32 (rahat 36) | 44 (sık 56) | 44 (sık 56) |
| Gövde metni | 14 | 17 | 17 |

## 6. T-019 için ilk prototip ekran listesi (`scenes/dev/ui_lab`, MockSimFacade, MOCK rozetli)
1. **HUD iskeleti**: üst şerit (zaman kontrolü, tarih, para), mod/araç çubuğu, bildirim şeridi, MOCK banner.
2. **Profil önizleme**: masaüstü ↔ dokunmatik ↔ iPad dikey düzen geçişi (güvenli alan simülasyonu, ≥44 pt hedef denetimi).
3. **L2 panel kabuğu**: sağ panel / alt sayfa, kapat-sabitle, durum bileşenleri (yükleme/boş/hata/kurulmamış/devre dışı).
4. **Denetçi** (parsel + ilçe) mock `ParcelView` ile.
5. **Nedensellik paneli** mock `ReasonRecord` zinciriyle (etken listesi, zincir, zaman).
6. **Ölçek kapısı** davranışı (`zoom.locked_here`) sahte kamera ölçeği olayıyla.
Sonra T-020 (1-3-4 gerçek), T-021 (5), T-022 (imar/meclis/bütçe akışları).
Kabul ölçütü ekleri: panel açıkken harita merkezi ≥ yarı görünür (ekran görüntüsü ölçümü); tüm metinler `UiText` üzerinden; `grep` ile gömülü metin yok.

## 7. T-019 uygulama notları (uygulamadan çıkan düzeltmeler)
- **Ölçek kuralı:** boyut = `max(taban × ui_scale, dokunmatik alt sınırı)`; taban belirteçler `data/ui/ui_tokens.json`. Dokunmatik taban ölçek `PlatformProfile.DEFAULTS` değeridir (şu an 1,25; §1'deki 1,15 önerisinin yerine geçer: gövde 14 × 1,25 = 17,5 ≥ 17 pt). Kullanıcı ölçeği küçültse de dokunmatikte 44/56 pt, gövde 17, yardımcı 13 alt sınırları korunur.
- **Sık hedef** masaüstünde 38, dokunmatikte ≥ 56 (§3.2); masaüstü rahat hedef 36.
- **Panel genişliği** masaüstünde `min(400 × ölçek, %28)`: 1280 pencerede ≈ 358 (§2'deki "360" ile %28 tavanı çakışır; tavan öncelikli).
- **Dikey alt sayfa** araç çubuğu DAHİL en çok %45 yüksekliktir; böylece ekran merkezi hiçbir zaman örtülmez (ölçüt: harita merkez bölgesinin ≥ %50'si görünür, `HudLayout.center_visible_fraction`).
- **Üst şerit** dar çerçevede (dikey iPad 834/1024) iki satıra sarılır: tarih ve para ikinci satıra iner; yükseklik içerikten gelir.
- **Kurulmamış modlar** (İnşa, Yönetim; T-022 öncesi) araç çubuğunda gizlenmez, devre dışı + "Henüz kurulmadı" etiketiyle görünür.
- **Sabitle** = sabit panel Esc/seçim temizleme gibi dolaylı kapanmalarda kapanmaz; yalnız Kapat düğmesiyle kapanır. Sürüklenebilir alt sayfa tutamağı v0'da YOK (ölü kontrol olmasın diye).
