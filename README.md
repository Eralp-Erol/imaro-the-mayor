# Belediye Tycoon — Codex başlangıç paketi

İçerik:
- `ULTIMATE-CODEX-PROMPT.md`: Codex'e ilk oturumda verilecek ana görev.
- `AGENTS.md`: Codex'in otomatik okuyacağı kalıcı proje ilkeleri.
- `references/`: Kullanıcı tarafından beğenilen görsel yönü gösteren 8 seçilmiş konsept.

## Kullanım

1. Bu klasörü Mac'inde istediğin yere çıkar. Yeni GitHub repo'yu bağlamak istersen `git init` sonrası remote ekle.
2. Godot 4 stable ve Codex CLI kurulu olsun.
3. Bu klasörde Codex Local oturumu aç. Model `gpt-6-astra`, efor `xhigh`; ilk mimari denemede Codex destekliyorsa `max` de denenebilir.
4. Codex'e `ULTIMATE-CODEX-PROMPT.md dosyasındaki görevi references/ görsellerine bakarak şimdi uygula.` de, veya dosyanın tüm metnini ilk mesaj olarak yapıştır.
5. Kod üretildikten sonra gerçek Godot screenshot'larını ve gameplay loop testlerini incele; yanlış temel varsa yeni repo/branch ile yeniden denemek daha iyi olabilir.

Açıklama: Bu paket bir oyun veya Godot projesi değil, ilk Codex oturumunu doğru temelle başlatmak için görev + referans paketidir.
