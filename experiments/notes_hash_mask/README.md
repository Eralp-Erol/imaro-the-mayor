# notes_hash_mask: `_notes` hash dışı kararının maske kanıtı (2026-11-07)

Tek kullanımlık deney; üretime import edilmez, `tools/verify.sh` kapsamında değildir.
Karar: `production/log/2026-11-07-teknik-direktor-notes-hash.md` (Konu 1).

Sav: `ActorConfig` özetinden `_` önekli üst düzey anahtarları çıkarmak 4 GOLDEN sabitinin TEK farkı `systems.actors.config_digest`
dizgisidir; sim gidişatı aynıdır. Kanıt: senaryoyu YENİ kodla koş, bitiş durumundaki `config_digest`i ESKİ yöntemle
hesaplanan özetle (`StateHash.of({dosya: to_ints(ham, _notes DAHİL)})`) değiştir, `state_hash()` ESKİ GOLDEN'a bit-bit eşit olmalı.
Eski değerler bu dosyalarda sabit yazılıdır (testlerdeki sabitler yenilense de kanıt tekrarlanabilir).

Çalıştırma (kilit: `mkdir /tmp/imaro-godot.lock`):
  tools/godot.sh --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://experiments/notes_hash_mask -c --ignoreHeadlessMode -rd /tmp/x -rc 1
Her dosyada `test_mask_*` kanıt testidir; üst sınıftan miras kalan testler de koşar (yenilenmiş sabitleri yeni kodla denetler).

Kontrol: eski özet, yeni özetten FARKLI olmalı (yoksa maske hiçbir şey yapmamıştır).
