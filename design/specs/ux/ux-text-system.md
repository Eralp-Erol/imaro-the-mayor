# Metin sistemi v0 (T-018 ölçüt 5)

Statü: ÇALIŞMA MODELİ. Tablo: `data/ui/strings.tr.json` (anahtar tabanlı, düz sözlük). Doğrulayıcı: `tests/ui/strings_table_test.gd` (hat testi). İlkeler `product-content-strategist` yaklaşımından: oyuncunun görevini söyle, kısa ol, bir terim bir anlam.

## 1. Mimari kurallar
1. **Gömülü metin yasağı.** `src/ui/`, `scenes/ui/` içinde oyuncuya görünen hiçbir Türkçe/İngilizce literal yoktur; her metin `tr("anahtar")` benzeri tek bir `UiText.get(key, args)` katmanından gelir (T-019 uygular; Godot `translation` CSV/PO'ya geçiş kolay kalsın diye anahtarlar `alan.alt.ad`). Dev-only etiketler `dev.` ön ekiyle ve yalnız `scenes/dev/` içinde.
2. **Varsayılan dil Türkçe** (Q-003 çalışma varsayımı, ÇM); dosya adı dili taşır (`strings.tr.json`), ek dil = yeni dosya, kod değişmez. Eksik anahtar: geliştirmede açık hata + ekranda anahtar adı; yayında `common.unknown` değil **anahtar adı** gösterilir (sessiz boş yok).
3. **Yer tutucu** `{ad}` küçük harf/alt çizgi; sıra bağımsız (adlandırılmış). Çoğul: Türkçe sayıdan sonra tekildir (`{n} gün`); ayrı çoğul anahtarı gerekmez.
4. **Sim metni üretmez.** Sim `ReasonRecord`/`SimEvent` içinde **anahtar + argüman** verir (`reason.factor.<key>`, `outcome` enum); UI Türkçeye çevirir. Sim çıktısında hazır Türkçe cümle yoktur (yerelleştirme + determinizm).
5. Sim'den gelen anahtar tabloda yoksa gerekçe satırı `anahtar adı` ile gösterilir ve geliştirme günlüğüne yazılır (T-021 kabul ölçütü). Etken anahtarları (`reason.factor.*`) ilgili sim görevleri ekledikçe tabloya eklenir; v0'da yer tutucu aileler `reason.outcome.*`.
6. **Kanon adları sabit string değildir:** parti, grup, ilçe (Orven hariç kesin ad yok), mahalle adları veri/yapılandırmadan gelir; tablo yalnız yer tutucu etiket içerir (`election.party.placeholder`, `record.group.placeholder`, `district.code`). Hiçbir ad ya da sayı konsept görselinden alınmaz (VIS-07).

## 2. Para (Q-003)
- Tutarlar sim'de birimsiz tamsayıdır. Gösterim `format.money`: `{amount} {currency}`; `{currency}` **yalnızca** yapılandırmadan (`economy.currency_symbol`, geçici `¤`) gelir; ad gerekiyorsa `economy.currency_name`. Tablo, belge ve testte ₺, TL, "lira" vb. bulunmaz (test bunu engeller).
- Büyük tutar kısaltması (bin/milyon) **kullanılmaz** v0'da; `1.234.567 ¤`. Kısaltma ihtiyacı doğarsa Türkçe "bin/milyon" yapılandırılabilir yardımcıyla, sembolsüz.
- İşaretli fark: `format.delta_plus/minus` (gerçek eksi işareti −).

## 3. Sayı, tarih, zaman
| Tür | Biçim |
|---|---|
| Ondalık/binlik | Türkçe: `1.234,5` (binlik nokta, ondalık virgül). Biçimleme tek yardımcıda (locale ayarlı); sim tamsayısı bölünerek gösterilir. |
| Yüzde | `%` sonda bitişik `42%` (`format.percent`); yalnız gerçek oran alanları; **memnuniyet/mutluluk yüzdesi yok** (SIM-09). Test: "mutluluk" geçen metin reddedilir. |
| Aralık | `a – b` (`format.range`), belirsizlik gösterirken (anket) |
| Oyun içi tarih | `clock.date_ingame` yer tutucu (`{year}. yıl, {day}. gün`); ay adları/takvim AÇIK. Gerçek dünya tarihi/saat biçimi oyun içinde kullanılmaz. |
| Süre | `{n} gün`; kısa süreler "saat" ancak sim saat veriyorsa |
| Birim | metrik; birim her zaman değerin yanında |

## 4. Ton ve yazım kuralları
- **Ton:** sakin, resmî değil ama ciddi; bir belediye başkanının çalışma masası. Ünlem yok, emoji yok, mizah yok, abartı yok.
- **Düğmeler:** fiil kökü/ad-fiil, tek-iki kelime, cümle başı büyük (`Onayla`, `Vazgeç`, `Meclise sun`). "Tamam" yalnız bilgi iletişiminde.
- **Hitap:** doğrudan hitap kaçınılır; edilgen/yalın ("Burada çizilemez"). Zorunlu olduğunda "siz".
- **Kısaltma:** yasak (ör. "yat." yerine "yatırım"). İstisna: `D1` gibi kod, `1×` hız, `%`. İlk geçişte açılım gerekmeyen yaygın kısaltmalar da yazılmaz.
- **Terim sözlüğü** (bir terim bir anlam): *İmar* (arazi kullanımı kararı) · *Yoğunluk* · *Yükseklik* · *Parsel* · *Gerekçe* (sim'in kaydettiği neden) · *Etken* (gerekçeyi oluşturan unsur) · *Sicil* (oyuncunun ayrı göstergeleri; "puan"/"skor" demeyiz) · *Grup* (seçmen/çıkar grubu; yer tutucu "Grup n") · *Öneri* (imar/bütçe teklifi) · *Meclis*.
- **Yasak kelimeler (CAN-03/SIM-09):** "bina yerleştir/dik", "mutluluk", "puan/skor" (sicil için), "seviye atla" (CAN-10).
- **Hata/engel mesajı kalıbı:** *ne oldu* + *neden (sim gerekçesi)* + *ne yapılabilir*. Örn. `draw.blocked.title` + `draw.blocked.reason`.
- **Kurulmamış sistem:** `… henüz kurulmadı`; vaat/tarih verme.
- **Sayılar sahte değil:** metinde örnek sayı, "Örn. 1000" gibi içerik yoktur.
- **Büyük harf:** Türkçe i/İ, ı/I; `to_upper()` kullanma (Godot yerel kuralı bilmez) — stil gerekiyorsa tabloda ayrı değer.
- **Uzunluk:** düğme ≤ 18 karakter, başlık ≤ 28, bildirim ≤ 80, ipucu ≤ 120; kabarma payı layout'ta.

## 5. Anahtar adlandırma
`alan.alt_alan.ad` (küçük harf). Alanlar: `app, common, mode, zoom, district, clock, tool, draw, zoning, inspector, reason, alert, council, budget, record, election, state, menu, settings, a11y, format`. Enum değerleri anahtar sonuna: `reason.outcome.investor_declined`. Sim enum → anahtar eşlemesi veri-odaklıdır (`reason.outcome.<enum_adı_snake>`), UI'da `match` yazılmaz.
Not: `_meta.*` anahtarları yalnız dosya üst verisidir.
