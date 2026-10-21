# Imaro otonom çalıştırma protokolü (zamanlanmış/yeniden başlayan oturumlar için)

Bu belge, kullanıcının "kesintisiz otonom geliştirme" talimatını (2026-10-21) uygulayan **taze bir Claude oturumunun** izleyeceği adımlardır.
Oturumun önceki sohbet belleği YOKTUR: durum yalnız repoda ve `~/.local/state/imaro-autonomy/` altındadır. Çalışma dizini:
`/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb` (dal `agent/handover-imaro-m01-349562fb`). main'e merge/push/deploy YOK.

## 0. Durdurma ve kilit (çakışmayı önler)
1. `~/.local/state/imaro-autonomy/STOP` varsa HEMEN çık ("durduruldu" de). Kullanıcı bu dosyayı koyarak sistemi durdurur.
2. `~/.local/state/imaro-autonomy/lock.json` oku. `{"holder": "...", "epoch": <saniye>}`; `epoch` şimdiden **50 dakikadan yeni** ise başka bir oturum çalışıyor:
   hiçbir şey yapma, "meşgul" yazıp çık. Eski/yoksa kilidi al: `{"holder": "<kısa ad>", "epoch": <şimdi>}` yaz. Her büyük adımda `epoch`'u yenile.
3. Çıkarken (iş bitti/kota/engel) kilidi sil. Beklenmedik kesilmede kilit 50 dk sonra bayatlar ve sonraki oturum devralır.

## 1. Yönelim (ucuz)
`docs/agent-handoff/IMARO_CHECKPOINT.md` §0 · `production/M2-CONTRACT.md` · `production/autonomy/QUEUE.md` (kuyruk + durum) · `git status` / `git log -5`.
Ağaç kirliyse: kimin işi olduğunu anla (önceki oturumun yarım işi olabilir); silme/sıfırlama YOK; tamamla ya da kaydet.

## 2. Görev seç
`QUEUE.md`'de bağımlılıkları `done` olan, durumu `ready|in-progress` olan ilk görev. `blocked` olanı atla. Hiçbiri yoksa: durumu yaz, kilidi sil, çık.

## 3. Görev protokolü (her görevde aynı; `production/M2-CONTRACT.md`)
1. Kısa kapsam: `production/tasks/T-0NN.md` (ölçütler + REQ + kanıt planı) ve `production/acceptance/T-0NN.json` (varsa) oku/tamamla.
2. Implementasyon: ilgili stüdyo uzmanını **Agent** aracıyla çağır (simulation-engineer / godot-engineer / world-engineer / ui-engineer / technical-artist;
   model her zaman açık: `sonnet`, büyük karar/inceleme için `opus`; **Haiku yasak**). Aynı dosyalara iki yazıcı yok; sıralı çağır. Uzman git YAZMAZ; sen commit'lersin.
3. Odaklı test: görevin testleri + `tools/lane.sh verify <hat>` + `uvx --from gdtoolkit==4.5.0 gdlint src tests`. Tam doğrulama yalnız teslimde/ihtiyaçta; `tools/smoke_playable.sh` teslimde bir kez.
4. Bağımsız QA: uygulayıcıdan FARKLI bir Agent (qa-engineer, `sonnet`/`opus`) gerçek runtime ile doğrular; rapor `production/qa/T-0NN-qa.md`
   (`VERDICT: PASS|FAIL`, `## Kanıt`, `## Bulgular`, `## Doğrulanmadı`). FAIL → bulguları giderme turu (en çok 2 tur), sonra yeniden QA.
5. Commit (path-scoped, `Co-Authored-By` satırı) → `production/tasks/T-0NN.md` Kanıt + `QUEUE.md` durum + `docs/agent-handoff/IMARO_CHECKPOINT.md` §0 güncelle → commit.
6. Bir sonraki göreve geç. Bir oturumda en çok **2 görev**; sonra kilidi bırakıp çık (sonraki zamanlanmış oturum sürdürür).

## 4. Değişmez kurallar
- `design/foundation/` değişmez; AÇIK yaratıcı kararlar (Q-003, Q-005…Q-015, partiler/rakipler/protagonist) KESİNLEŞTİRİLMEZ: veri-odaklı geçici + `production/QUESTIONS.md` grubu.
- Kullanıcı/cihaz onayları (Q-015, iPad, Windows, art-director, kullanıcı incelemesi) UYDURULMAZ; `AÇIK — kullanıcı/cihaz` olarak kayıtlı kalır, geliştirmeyi durdurmaz.
- CAN-03: oyuncu özel bina spawn edemez; HUD yalnız gerçek sim verisi; sim saf/deterministik. Başarısız testi PASS gösterme, eşik gevşetme, yavaş kareleri ölçümden çıkarma.
- main'e merge, push, force push, deploy, izin ayarı/CLAUDE.md değiştirme YOK. Yalnız KENDİ başlattığın PID'i öldür. Başka oturumun işine dokunma.
- Aynı Godot cache'i paylaşıldığından AYNI ANDA tek Godot koşusu (özellikle pencereli yakalama/perf).
- Engel/tekrarlayan hata: görev dosyasına `Durum: ENGELLİ — <neden>` + `QUEUE.md`'de `blocked`; bağımsız sonraki göreve geç. Sonsuz döngü yok: görev başına en çok 3 deneme (`QUEUE.md` "Deneme").
- Kota/limit dolarsa: işi commit'le, checkpoint bırak, kilidi sil, çık (sonraki oturum sürdürür).

## 5. Her çıkışta bırakılacaklar
Commit'li ağaç (yarım iş varsa `docs/agent-handoff/wip/` yedeği + checkpoint notu), `QUEUE.md` güncel, `IMARO_CHECKPOINT.md` §0 güncel, kilit silinmiş.
