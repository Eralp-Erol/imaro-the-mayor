# tools/ — doğrulama ve derleme altyapısı

Hepsi bash 3.2 uyumlu (`set -euo pipefail`). Godot 4.7.2.stable zorunlu; ikili `tools/godot.sh` ile bulunur.

| Komut | Ne yapar | Çıkış kodu / çıktı |
|---|---|---|
| `tools/godot.sh <godot args>` | İkiliyi çözer (`$IMARO_GODOT` → ana checkout `.tools/Godot.app` → `/Applications/Godot.app`), sürümü doğrular, `exec` eder. `--path` eklemez. | 2 = ikili yok, 3 = sürüm uyumsuz (`IMARO_GODOT_ALLOW_VERSION_MISMATCH=1` ile geçilir) |
| `tools/godot.sh --print-path` | Çözülen ikilinin yolunu basar. | 0 |
| `tools/fingerprint.sh` | `src scenes tests addons assets project.godot` çalışma ağacı içeriğinin tek sha256'sı (izlenen + izlenmeyen, ignore hariç, `*.uid` hariç). | stdout: hash |
| `tools/verify.sh quick` | canon-check, gdlint, import, GdUnit4 (başsız, ~25 sn). | 0 = pass, 1 = fail; `artifacts/verify/quick-latest.json` |
| `tools/verify.sh full` | quick + pencereli runtime smoke (180 kare, `run/main_scene` ile). Ana sahne yoksa (`no main scene yet`) veya `IMARO_NO_WINDOW=1` ise `skip`. | `artifacts/verify/full-latest.json`, günlükler `artifacts/verify/*.log` (git'te yok) |
| `tools/capture.sh <ad> [--frames N] [--resolution WxH] [--scene res://x.tscn] [-- ekstra]` | Sahneyi (varsayılan `run/main_scene`) pencereli açıp N kare sonra PNG alır (`tools/godot/capture_frame.gd`). Ana sahne ve `--scene` yoksa skip: stderr mesajı, çıkış 0, stdout boş. | stdout: `artifacts/screenshots/captures/<tarih>-<ad>.png` |
| `tools/perf.sh <ad> [--frames N] [--warmup N] [--resolution WxH] [--scene res://x.tscn] [-- ekstra]` | Sahneyi (varsayılan `scenes/dev/world_preview.tscn`) pencereli açıp kare süresi (VSync kapalı), draw call, obje/üçgen, bellek ölçer (`tools/godot/perf_probe.gd`); ilk N kare ısınma. GPU süresi Compatibility'de ölçülemez. | stdout: `artifacts/perf/<tarih>-<ad>.json` + özet satırı (yük ortalaması dahil) |
| `tools/visual-diff.sh a.png b.png [fark.png]` | `magick compare -metric AE -fuzz 2%`; farklı piksel sayısı ve yüzde. Eşik kararı çağırana ait. | 0 (araç hatası 1, boyut farkı 2); stdout: `diff_pixels=N total=M percent=P` |
| `tools/export.sh <macos|windows|ios> [--release]` | Export (T-007): `build/<platform>/<debug|release>/`. Alt komutlar: `smoke macos` (.app açılış duman testi), `templates`, `install-templates <tpz>` (boyut + SHA-512 doğrular). İndirme YAPMAZ; şablon yolu `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`. iOS imza/takım bilgisi repoya girmez. | 0 ok, 1 export/duman hatası, 2 kullanım, 3 sürüm, 4 şablon yok, 5 SHA-512 |
| `tools/canon-check.sh` | `design/foundation` manifest bütünlüğü (başka ajan yazdı). | 0/1 |

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
