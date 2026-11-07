# tools/ — doğrulama ve derleme altyapısı

Hepsi bash 3.2 uyumlu (`set -euo pipefail`). Godot 4.7.2.stable zorunlu; ikili `tools/godot.sh` ile bulunur.

| Komut | Ne yapar | Çıkış kodu / çıktı |
|---|---|---|
| `tools/godot.sh <godot args>` | İkiliyi çözer (`$IMARO_GODOT` → ana checkout `.tools/Godot.app` → `/Applications/Godot.app`), sürümü doğrular, `exec` eder. `--path` eklemez. | 2 = ikili yok, 3 = sürüm uyumsuz (`IMARO_GODOT_ALLOW_VERSION_MISMATCH=1` ile geçilir) |
| `tools/godot.sh --print-path` | Çözülen ikilinin yolunu basar. | 0 |
| `tools/fingerprint.sh` | `src scenes tests addons assets project.godot` çalışma ağacı içeriğinin tek sha256'sı (izlenen + izlenmeyen, ignore hariç, `*.uid` hariç). | stdout: hash |
| `tools/verify.sh quick` | **Hızlı, kapsamlı doğrulama (hedef <= 5 dk):** canon-check, studio-check, area-map (eşleme tutarlılığı), gdlint, import + GdUnit4'ün yalnız **koruma çekirdeği** (her zaman) ve **değişen alanın** suite'leri. Değişen dosyalar `git diff` (son başarılı doğrulamanın HEAD'ine göre; yoksa `main` ayrışma noktası) + izlenmeyenlerdir; `tools/verify-areas.tsv` ile suite'lere çevrilir. Eşlemesiz yol varsa güvenli yönde tüm suite'ler koşar. Çıktıda `kapsam:` ve `ATLANDI:` satırları vardır; **quick PASS tam doğrulama değildir** (JSON: `scope: "changed-areas"`, `full_verification: false`). | 0 = pass, 1 = fail; `artifacts/verify/quick-latest.json` |
| `tools/verify.sh full` | quick'in adımları, ama GdUnit4'ün **tüm** testleri (`scope: "full"`, makine yük altında ~21 dk) + canon-guard (C-07) + pencereli runtime smoke (180 kare, `run/main_scene` ile). Ana sahne yoksa (`no main scene yet`) veya `IMARO_NO_WINDOW=1` ise runtime `skip`. **Milestone/teslimde.** | `artifacts/verify/full-latest.json`, günlükler `artifacts/verify/*.log` (git'te yok) |
| `tools/capture.sh <ad> [--frames N] [--resolution WxH] [--scene res://x.tscn] [-- ekstra]` | Sahneyi (varsayılan `run/main_scene`) pencereli açıp N kare sonra PNG alır (`tools/godot/capture_frame.gd`). Ana sahne ve `--scene` yoksa skip: stderr mesajı, çıkış 0, stdout boş. | stdout: `artifacts/screenshots/captures/<tarih>-<ad>.png` |
| `tools/perf.sh <ad> [--frames N] [--warmup N] [--resolution WxH] [--scene res://x.tscn] [-- ekstra]` | Sahneyi (varsayılan `scenes/dev/world_preview.tscn`) pencereli açıp kare süresi (VSync kapalı), draw call, obje/üçgen, bellek ölçer (`tools/godot/perf_probe.gd`); ilk N kare ısınma. GPU süresi Compatibility'de ölçülemez. | stdout: `artifacts/perf/<tarih>-<ad>.json` + özet satırı (yük ortalaması dahil) |
| `tools/godot.sh --headless --path . --script res://tools/godot/vegetation_probe.gd -- [--no-cache] [--preset=...] [--cam=x,y,z] [--colors]` | Bitki tanısı (T-062 B1), başsız: oyunun dünya kurulumu + `VegetationLoader` (önbellek/üretim süresi), örnek/tür sayıları, kamera noktası başına kademe örnek/üçgen ve leke üçgeni. Render/FPS ölçmez. | stdout `VEG_PROBE ...` satırları |
| `tools/godot.sh --headless --path . --script res://tools/godot/road_ux_probe.gd -- [--n=200]` | Yol çizimi maliyeti, başsız, GERÇEK Ismeral dünyası: `RoadDraftCheck.check` (geçerli/reddedilen), yol onayı bölümleri (add_road, begin_async, arka plan, install: ana iş parçacığı vs duvar), imleç adımı başına panel yeniden çizimi. Render/FPS ölçmez. | stdout `ROAD_UX...` satırları |
| `tools/godot.sh --headless --path . --script res://tools/godot/k1_table.gd` | K1 tablosunu (ADR-0007 §Bağlam) `CameraEnvelope` ile yeniden üretir (T-064): bölge çapası başına gereken eğim ve en büyük uzaklık, dışa/içe yön. Düz deniz düzlemi, 16:9 ve 4:3. | stdout `K1_TABLE ...` satırları |
| `tools/visual-diff.sh a.png b.png [fark.png]` | `magick compare -metric AE -fuzz 2%`; farklı piksel sayısı ve yüzde. Eşik kararı çağırana ait. | 0 (araç hatası 1, boyut farkı 2); stdout: `diff_pixels=N total=M percent=P` |
| `tools/export.sh <macos|windows|ios> [--release]` | Export (T-007): `build/<platform>/<debug|release>/`. Alt komutlar: `smoke macos` (.app açılış duman testi), `templates`, `install-templates <tpz>` (boyut + SHA-512 doğrular). İndirme YAPMAZ; şablon yolu `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`. iOS imza/takım bilgisi repoya girmez: `IMARO_IOS_TEAM_ID` zorunlu (bkz. «iOS kurulumu»). | 0 ok, 1 export/duman hatası, 2 kullanım, 3 sürüm, 4 şablon yok, 5 SHA-512, 6 iOS takım kimliği/ikon |
| `tools/ios-install.sh --device <id> [--release] [--no-export] [--register-device]` | iOS: export -> `xcodebuild` (otomatik imza) -> `xcrun devicectl device install app` -> başlatma (`com.imaro.themayor`). `--build-only` imzasız derleme (cihaz gerekmez), `--list-devices`, `--launch-only`. Takım kimliği/cihaz ortamdan veya argümandan; sabit yok. | 0 ok, 1 derleme/kurulum, 2 kullanım, 6 takım kimliği/cihaz eksik |
| `tools/ios-placeholder-icon.py [çıktı.png]` | YER TUTUCU iOS ikonu (1024x1024, sarı/siyah şerit + «YER TUTUCU / SAHİP İKONU BEKLİYOR»). Gerçek ikon DEĞİL; `tools/export.sh ios` export öncesi `build/ios/placeholder-icon.png` olarak (gitignored) üretir. | 0; stdout: yazılan yol |
| `tools/verify-scope.sh check|resolve <dizin>|base` | `verify quick` kapsam çözücüsü. `check`: `tools/verify-areas.tsv` tutarlı mı (her `src/` dizini bir kurala bağlı, her test belirteci suite'e çözülüyor). `resolve <dizin>`: değişen dosyalardan `run.txt` / `skip.txt` / `areas.txt` üretir (quick'in ne koşacağını önceden görmek için). `base`: kullanılacak taban. | 0/1 |
| `tools/canon-check.sh` | `design/foundation` manifest bütünlüğü (başka ajan yazdı). | 0/1 |

## Cihaz/oyun içi kare ölçümü (T-076, ADR-0010)
`src/view/perf/perf_logger.gd` (`PerfLogger`): oyun içi, yalnız `--perf-log[=ad|yol]` bayrağı, `IMARO_PERF_LOG` ortam değişkeni ya da `perf_log` özellik etiketiyle `scenes/dev/world_preview.gd` (playable'ın tabanı) altına eklenir; kapalıyken düğüm hiç oluşmaz. Kare süresi (ort/p50/p95/p99/maks), tick'li/tick'siz ayrımı, çizim çağrısı, üçgen ve en kötü 20 kare (kare no, ms, sim günü) JSON olarak `user://perf/` altına yazılır (aralıklı, `--perf-log-frames=N` karesinde, çıkış/arka plana alınınca). Masaüstü: `tools/godot.sh --path . res://scenes/game/playable.tscn -- --demo --perf-log=ad.json --perf-log-frames=6000` (dosya macOS'ta `~/Library/Application Support/Godot/app_userdata/<proje>/perf/`). `tools/ipad-pull-perf.sh --device <kimlik> [--list] [--dry-run]`: iPad uygulama kapsayıcısından dosyayı `xcrun devicectl device copy from` ile `artifacts/perf/ipad-<tarih>/` altına çeker (cihaz kimliği argüman/`IMARO_IPAD_DEVICE`; kaynak yolu `Documents/perf` varsayımdır, gerçek cihazda doğrulanmadı). `busy_ms` (karenin ilk `physics_frame`/`process_frame`'inden `frame_post_draw`a CPU meşgul süresi; döküm `pre_draw_ms`, `render_cpu_ms`; `utilization`; ısıl pencerelerde `busy_ms_p95`; `refresh_hz_changed`) ADR-0010 Karar 3a'dır, masaüstü kalibrasyonu `production/log/2026-11-06-busy-ms-kalibrasyon.md`. Ölçüm tanımı perf_probe ile aynıdır (en yakın sıra yüzdeliği); iPad sayıları bu Mac'in sayılarıyla karıştırılmaz. `tools/ipad-series.sh`: TD koşu kitabı serisi (15 dk soğutma, 5 kısa, 1 render-ölçümsüz, 300 sn, 3 sıcak koşu); ortamdan `IPAD`, `CD`, `IMARO_IOS_TEAM_ID` ister (repoya kimlik yazılmaz), sahip ön koşulları onaylayınca `touch $IMARO_SERIES_GO` (varsayılan `/tmp/ipad-series.go`) ile başlar; her koşu benzersiz adlı, dosya `started_unix` başlatmadan eskiyse "bitti" sayılmaz; yan kayıt `devicectl info displays|lockState` (içeriği cihazda doğrulanmadı). Çalıştırılmadı: yalnız sözdizimi denetlendi.

## Kamera zarfı bayrağı (T-064, ADR-0007)
Oyuncu kamerası `data/view/camera_envelope.json` `player` zarfındadır (~18 km tavan, ~50 m, K1). Eski 58 km / 25 m / 8 derece durumu yalnız geliştirici bayrağıyla verilir: `--envelope=legacy` (+ `--preset=metro_legacy_bench`); dışa aktarılan sürümde yok sayılır. `metro` preset adı emekli (açık hata); yeni uzak uç `core`. `tools/capture.sh`, `tools/perf.sh` ve `tools/smoke_playable.sh` sahneye `-- ... --envelope=legacy` argümanını aynen iletir; `smoke_playable.sh` kabulü `core`, `district:D1`, `street:port` en kötüsüdür, `metro_legacy_bench` bilgi amaçlıdır. Geliştirici sahnede `Home` başlangıç görünümü, `M` core.

## iOS kurulumu (B-060..B-062; tekrarlanabilir, geçici yerel düzenleme gerekmez)
```
export IMARO_IOS_TEAM_ID=<10 karakterli takım kimliği>      # repoya yazılmaz; Apple Developer -> Membership
tools/ios-install.sh --list-devices                          # cihaz kimliğini/adını bul
export IMARO_IOS_DEVICE=<kimlik veya ad>
tools/ios-install.sh                                         # export + derle + kur + başlat
tools/ios-install.sh --register-device                       # YALNIZ ilk kurulumda, cihaz sahibinin onayıyla
tools/ios-install.sh --build-only                            # cihazsız: yalnız derlemenin çalıştığını doğrular
```
- **Ana sahne:** `project.godot` `run/main_scene` duman sahnesidir (test/CI/`verify`/`capture` değişmez);
  `run/main_scene.template` oyunu (`scenes/game/playable.tscn`) açar. `template` etiketi yalnız dışa aktarılan
  ikililerde (macOS/Windows/iOS) vardır; editör ve `godot --path` çalıştırmaları etkilenmez. Gerekçe: özellik etiketi
  tek satır; geçici dosya veya geri alma yok (kesilirse kalıntı bırakacak adım yok). `export.sh smoke macos`
  duman sahnesini .app içine geçici `override.cfg` yazarak seçer (şablonlar komut satırı sahne yolunu reddeder).
- **Takım kimliği:** `export_presets.cfg`'de BOŞ kalır (`tests/app/export_tooling_test.gd` zorlar). `tools/export.sh ios`
  `IMARO_IOS_TEAM_ID`'yi export süresince Godot'nun kendi kimlik bilgisi dosyasına (`.godot/export_credentials.cfg`,
  gitignored) yazar, çıkışta siler (editörün kendi dosyası varsa yedekleyip geri koyar); `ios-install.sh` ayrıca
  `DEVELOPMENT_TEAM=` verir. Yoksa/geçersizse çıkış 6 ve açık mesaj.
- **İkon:** preset `icons/icon_1024x1024` = `res://build/ios/placeholder-icon.png` (YER TUTUCU, sahip ikonu
  bekliyor). Gerçek ikon sahibin kararıdır; geldiğinde yalnız o preset yolunu gerçek PNG'ye çevir.
- **Ağ üzerinden kurulum:** iPad bir kez USB ile eşlenip Xcode > Window > Devices and Simulators'ta «Connect via
  network» açılırsa aynı Wi-Fi'da `xcrun devicectl list devices` cihazı gösterir ve betik USB'siz çalışır (TEST
  EDİLMEDİ; cihaz kilitsiz ve aynı ağda olmalı). İlk kurulumda iPad'de Ayarlar > Genel > VPN ve Aygıt Yönetimi'nden
  geliştirici onayı ve Geliştirici Modu gerekebilir.
- **Doğrulananlar / değil:** export (`export_project_only`) ve imzasız `xcodebuild` derlemesi bu Mac'te doğrulandı.
  İmzalı derleme, `devicectl install/launch`, cihazda açılış ve ağ üzerinden kurulum doğrulanmadı.


## JSON rapor alanları
`mode, started_at, git_head, fingerprint, steps[{name,status(pass|fail|skip),seconds,summary}], result`.
`fingerprint` doğrulama başında hesaplanır; kodu sonra değiştirdiyseniz `tools/fingerprint.sh` ile karşılaştırın.

## Notlar
- Unit testler GdUnit4 v6.2.2 (`addons/gdUnit4`, kendi `test/` klasörü çıkarıldı). Editör eklentisi olarak açmak GEREKMEZ.
  Elle: `tools/godot.sh --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests -c --ignoreHeadlessMode`
  (çıkış 101 = yalnızca uyarı, verify bunu geçer sayar).
- Lint: `uvx --from gdtoolkit==4.5.0 gdlint src tests`, ayarlar kökteki `gdlintrc` (satır limiti 120).
- `--headless` dummy renderer kullanır, görüntü alamaz: `capture.sh` ve runtime smoke gerçek pencere açar.
- GdUnit4 raporları `artifacts/verify/gdunit/` altına yazılır (`-rd` yolu res://-göreli verilmeli, mutlak yol bozuk iç içe dizin üretir).
- macOS'ta pencere 1 piksel eksik çıkabilir (örn. 1024x767); karşılaştırırken aynı `--resolution` kullanın.
