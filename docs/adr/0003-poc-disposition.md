# ADR-0003 · Eski POC'nin statüsü: silindi, temiz başlangıç

- Durum: kabul · Tarih: 2026-10-20 · Karar veren: kullanıcı (silme), technical-director (sonuçların kaydı)
- Karşıladığı gereksinimler: F06 "Önceki teknik POC'den öğrenilenler"; CAN-01

## Bağlam
2026-10-19 tarihli Codex POC'si (tek mahalle, 32 parsel, `src/`, `scenes/`, testler, `ULTIMATE-CODEX-PROMPT.md`, `references/01–08`, eski `docs/*`) kullanıcı tarafından beğenilmedi ve 2026-10-20'de ana checkout'tan **silindi** (izlenen 72 dosyanın 66'sı; yalnız `.codex/` ve `.gitignore` kaldı). Foundation F06 de POC'nin istenen şehir kimliğini kanıtlamadığını ve hiçbir kodun otomatik devralınmayacağını söylüyor.

Not: bu stüdyo kurulum dalı silme commit'lenmeden önceki commit'ten (`0c908b4`) açıldığı için POC başlangıçta burada yeniden göründü ve doğrulama altyapısı kurulurken bir kez çalıştırıldı. Fark edilince bu dalda da aynı dosyalar silindi.

## Karar
1. Üretim temiz başlar: repoda POC kodu, sahnesi, testi veya referans görseli yoktur. Boş bir `project.godot` yalnız doğrulama altyapısı için vardır.
2. POC yalnızca git geçmişinde (`0c908b4`) kalır. Bir parçası (ör. dokunma girdisi koordinat düzeltmesi, sabit tick birikimi) yeniden kullanılmak istenirse: teknik inceleme + kullanıcıya bildirim + yeni mimariye (ADR-0002) göre yeniden yazım. Doğrudan kopyalama yok.
3. POC'den çıkarılmış **dersler** (kod değil) geçerlidir: test girdisinin koordinat uzayı (mantıksal viewport vs pencere pikseli), görüntü yakalamada çizim kuyruğunun tamamlanmasını beklemek, iptal edilen dokunmaların temizlenmesi, `--headless` ile ekran görüntüsü alınamaması.
4. "Ilgın Belediyesi", "Kıyı Mahallesi" gibi POC adları kullanılmaz.
5. `.codex/` kullanıcı tarafından tutulduğu için dokunulmadı (Codex başlatıcısı; eski görevi tarif eder, kanon değildir).

## Sonuç
Sanat ve oynanış için repo içindeki tek yaratıcı kaynak `design/foundation/` (+ ileride `design/decisions/`).
