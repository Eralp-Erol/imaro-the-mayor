# Kullanıcı kararı bekleyen sorular

Yalnızca kanondan çözülemeyen, gerçekten yaratıcı/ürün kararları. Gruplanmış tutulur; her biri için stüdyonun beklerken ne yaptığı yazılıdır. Cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

Durumlar:
- **open** — çözülmemiş tasarım kararı; izlenir ama hiçbir görevi engellemez (stüdyo yapılandırılabilir/geri alınabilir biçimde ilerler).
- **blocked** — en az bir görevi durduruyor; `Engellediği` satırında görev kimlikleri yazılır.
- **answered → D-NNN** — kullanıcı karar verdi.

| Q | Konu | Durum | Engellediği |
|---|---|---|---|
| Q-001 | Eski POC referans görselleri | answered → D-001 | — |
| Q-002 | Başlangıç ilçesi | answered → D-002 | — |
| Q-003 | Anderva para birimi | **open** | — (engellemiyor) |
| Q-004 | Platform önceliği | answered → D-003 (+ D-004) | — |
| Q-005 | Protagonist: ad, geçmiş, görünüm, özelleştirme (AS-1) | **open** | — (engellemiyor) |
| Q-006 | Partiler: sayı, ad, ideoloji, eksenler; bağımsız adaylık (AS-2) | **open** | — |
| Q-007 | Seçim takvimi, başlangıç modu (aday / göreve gelmiş / ikisi), seçim kanunu, meclis usulü (AS-4, AS-8) | **open** | — |
| Q-008 | Kaybetme sonucu: kampanya sonu / muhalefet / karma (AS-5, CAN-10) | **open** | — |
| Q-009 | Rakipler, diğer altı metropolün liderleri, hikâye karakterleri; yazılı–sistem olayı dengesi; haber arşivi (AS-3, AS-9, AS-12) | **open** | — |
| Q-010 | İçerik tonu sınırları: yolsuzluk/çıkar çatışması sunumu, şiddet/taciz, etnik-dinsel konular, gerçek figür/olay benzerliği, hiciv (AS-6, AS-10, AS-13) | **open** | — |
| Q-011 | UX: HUD stili, açılış menüsü, istatistik biçimi, zoom akışı (sürekli/ölçek kapısı), tek/iki panel, olay kesintisi + otomatik duraklatma varsayılanı (ux-ia §9, AS-11) | **open** | — |
| Q-012 | Oyun içi takvim biçimi; Türkçe alt başlık istenip istenmediği | **open** | — |
| Q-013 | Yapı kiti: dini yapılar var mı; çatı payı oranları; T0'da 12+ kat; saat kulesi hedef boyu (T-025 S1–S4) | **open** | — |

### Q-001 · Eski 8 POC referans görselinin statüsü  (status: answered → D-001)
- Kullanıcı eski POC'yi referans görselleriyle birlikte sildi; kullanılmaz.

### Q-002 · İlk geliştirilecek (dikey dilim) ilçe  (status: answered → D-002)
- Oyuncu başlangıç ilçesini kendisi seçer; Orven zorunlu değil. Stüdyo, M2 için teknik test alanı seçebilir (Orven/D2) ama bu oyun tasarımı varsayımına dönüşmez.

### Q-003 · Anderva'nın para birimi  (status: open — engellemiyor; kullanıcı 2026-10-20'de bilinçli olarak AÇIK bıraktı)
- Kullanıcı: "Anderva'nın para birimi henüz kararlaştırılmadı. Bu konu OPEN kalacak. Gerekli sistemlerde yapılandırılabilir parametreler kullan; para birimi adı veya sembolü hakkında kanon oluşturma."
- Studio kuralı: para birimi adı/simgesi yalnız yapılandırmadan okunur (`economy.currency_name`, `economy.currency_symbol`); geçici gösterim nötr `¤` simgesidir; hiçbir belge, test veya UI metni ₺ ya da başka bir adı kanon gibi kullanmaz. Simülasyon tutarları birimsiz tamsayıdır.
- Arayüz dili: bu soruda cevaplanmadı; çalışma varsayımı Türkçe varsayılan arayüz, tüm metinler merkezi (ÇM). Şimdilik yeniden sorulmuyor.

### Q-004 · Hedef platform önceliği  (status: answered → D-003, cihaz bilgisi D-004)
- Masaüstü (Windows + macOS) birincil, iPadOS ikincil ama ilk günden mimaride. Uygulama: ADR-0004.

### Q-005…Q-013 · T-015/T-018/T-025 spec turundan gelen açık sorular (status: open — hiçbiri hiçbir görevi engellemez)
Kaynak: design-director canon kapısı (2026-10-20) ve art-director T-025 raporu. Ayrıntı ve gerekçe: `design/specs/characters-npc.md` §14 (AS-1..10), `design/specs/political-events.md` §12 (AS-11..13), `design/specs/ux/ux-ia-v0.md` §8–9, `design/specs/art/building-kit-v0.md` (S1–S4). Hiçbiri kanonlaştırılmadı.
Beklerken stüdyo ne yapar: protagonist `actor.protagonist` + boş `profile_slots`; partiler `party.a/b`, N veridir, M2'de parti yok; `T_elec`/`start_mode`/`election.rule`/`council.size` parametre; `lose_consequence` kancası; yalnız sistem tetikli olaylar, boş kadro şeması; `tone_profile` ılımlı yer tutucu, `corruption` etiketli şablonlar kapalı; HUD A iskeleti nötr tema, yalnız prototip, MOCK rozetli; takvim `{year}. yıl, {day}. gün`, başlık 'Imaro: The Mayor'; kit v0 varsayımları (dini yapı yok, çatı kiremit payı ≤%55 yakın/≤%35 metro, 12+ kat yalnız D1'de az, saat kulesi 23 m).
Tek sert kural: **ad/sayı/senaryo kanon gibi yazılmaz**; cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.
