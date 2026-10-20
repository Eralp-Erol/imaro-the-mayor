# Kanon dizini ve öncelik sırası

Bu dosya, Imaro stüdyosundaki her ajanın yaratıcı gerçeği **nereden** okuyacağını ve çelişkide **hangisinin kazanacağını** tanımlar. Yaratıcı otorite kullanıcıdadır (Creative Director). Ajanlar kanonu değiştiremez; yalnızca önerir ve `production/QUESTIONS.md` üzerinden sorar.

## Kaynaklar (yüksekten düşüğe öncelik)

| Sıra | Kaynak | Statü | Not |
|---|---|---|---|
| 1 | `design/decisions/` (tarihli, kullanıcı onaylı kararlar) | Kullanıcının sonraki açık kararları | Boş başlar. Yalnız kullanıcı onayıyla eklenir. |
| 2 | `design/foundation/` — IMARO_GAME_DESIGN_FOUNDATION 2026-10-20 | **Ana yaratıcı kaynak**; değiştirilemez | SHA-256 manifesti var (`tools/canon-check.sh`). İçindeki KANONİK / ONAYLANMIŞ YÖN / ÇALIŞMA MODELİ / AÇIK / REDDEDİLDİ etiketleri aynen geçerlidir. |
| 3 | `design/REQUIREMENTS.md` | Kaynak 2'nin izlenebilir özeti | Her satır kaynak bölüme bağlıdır; kaynakla çelişirse kaynak kazanır. |
| 4 | Silinmiş eski POC (kod, `ULTIMATE-CODEX-PROMPT.md`, `references/01–08`, eski `docs/*`) | **Kanon değil; kullanıcı tarafından 2026-10-20 silindi** | Yalnızca git geçmişinde (`0c908b4`). Hiçbir şey otomatik devralınmaz; bir bileşen ancak ayrı teknik incelemeyle ve kullanıcıya bildirilerek yeniden kullanılabilir (ADR-0003). "Ilgın" gibi POC adları kullanılmaz. |

## Çelişki çözümü (foundation 05'ten, aynen)

1. Kullanıcının daha sonraki açık düzeltmesi, eski görsel/belgedeki çelişkili ayrıntıdan üstündür.
2. Yazılı kural, referans görseldeki hatalı ayrıntıdan üstündür.
3. Onaylı görsel yön, bir objenin gerçek koordinatı veya teknik inşa kararı değildir.
4. Çalışma modeli, kullanıcı onayı olmadan isim/sayı/tek zorunlu senaryo olarak sabitlenmez.
5. Mimariyi gerçekten etkileyen belirsizlik açık alternatifler olarak değerlendirilir; kullanıcı adına karara dönüştürülmez.

## Silinmiş POC ile farklar (bilgi için)

Eski POC tek kurgusal mahalle ("Ilgın Belediyesi"), yol çizimi olmayan bir menü ve zorunlu Godot/iPad varsayımı kullanıyordu. Foundation bunların yerine Anderva → Ismeral → D1–D6, doğrudan belediye inşası (yol, meydan, park) ve açık teknoloji/platform kararı koyar. Özel bina yasağı iki dönemde de aynıdır.

## Açık yaratıcı kararlar

Foundation 05-D'deki açık kararlar **uydurulmaz**. Bir görev bunlardan birine dayanıyorsa iş ya kararı gerektirmeyecek biçimde (veri odaklı, değiştirilebilir) yapılır ya da `production/QUESTIONS.md`'ye gruplanmış soru olarak eklenir.
