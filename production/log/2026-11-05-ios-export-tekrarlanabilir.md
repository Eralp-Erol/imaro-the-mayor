# iOS export/kurulum tekrarlanabilir hale getirildi — 2026-11-05 (godot-engineer)

Bug kayıtları: `production/bugs/B-060.md` (ana sahne), `B-061.md` (yer tutucu ikon), `B-062.md` (takım kimliği + kurulum betiği).
Kullanım: `tools/README.md` «iOS kurulumu».

Değişen: `project.godot` (+`run/main_scene.template`), `export_presets.cfg` (iOS: yalnız `icons/icon_1024x1024` yer tutucu yolu; takım kimliği BOŞ), `tools/export.sh`, `tools/ios-install.sh` (yeni), `tools/ios-placeholder-icon.py` (yeni), `tools/README.md`.
Sahibin kararı olan hiçbir şey eklenmedi: gerçek ikon yok (açıkça YER TUTUCU), uygulama adı değişmedi, takım kimliği repoda yok.

Ölçümler/kanıt (Intel Mac; iPad DEĞİL): export (macOS+iOS, `export_project_only`) geçti; macOS .app başsız oyunu açtı (`PLAYABLE_SAVE_LOAD OK`); `export.sh smoke macos` ok; `ios-install.sh --build-only` -> `BUILD SUCCEEDED`; dev çalıştırması (`godot --path . --quit-after 180`) hâlâ duman sahnesi (`IMARO_SMOKE_OK`); `smoke_playable.sh` başsız faz geçti.
Test edilmedi: imzalı derleme, `devicectl install/launch`, `--register-device`, ağ üzerinden kurulum, cihazda açılış/ikon görünümü.

verify quick (project.godot ALL eşlemesi yüzünden 307/307 suite, tam doğrulama DEĞİL: canon-guard atlandı, pencereli runtime/perf yok): PASS, 3016 test, 0 hata, 1753 sn (VERIFY_UNIT_TIMEOUT=3000; ilk koşu varsayılan 1200 sn zaman aşımına uğramıştı, hata değil). İlk kapsamlı önizlemede tests/app/export_tooling_test.gd yer tutucu takım kimliğini yakaladı; yöntem değiştirildi (B-062).
