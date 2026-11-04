# Oyun tabloları (T-062 A0, ADR-0006 §2.1a)

`tools/library/build_game_set.py` kataloğdan oyunun okuyacağı tabloları üretir: `data/library/game_buildings.json` (21 hero bina, `modules[]`) ve `data/library/game_ground.json` (14 zemin dokusu, `layers[]`).

## Kapı
Kayıt yalnız şu üç koşul birlikte sağlanırsa girer: `approval == approved`; `user_approved_sha256` == kataloğun GÜNCEL içerik hash'leri (`apply_approvals.content_hashes`); diskteki GLB/PNG dosya hash'leri kataloğa eşit. Aksi halde çıktıya GİRMEZ, `unapproved` altında `count`, `by_reason` ve `entries[{id, reason, detail}]` olarak yazılır. Nedenler: `not_approved`, `no_approved_hash`, `hash_drift` (detay = uyuşmayan hash anahtarları), `file_missing`, `file_drift`. Oyun bu sayıyı `unapproved` diye raporlar. Kimlik listesi katalogdan türetilir, kodda gömülü liste yoktur. Çıktı `source_catalog_sha256` taşır; sıralı, sabit biçim, zaman damgası yok (bayt-eşit tekrar).

## Bina alanları ve kaynakları
- Ölçülen (GLB `POSITION` min/max, üçgen): `lods.*.aabb_m`, `tris`, `footprint_m` (LOD0 bbox XZ), `height_m`.
- Üreteç parametresi (Blender betiklerinin saf-Python düzen modülleri, `bpy` yok): `generator_params` = `floors` (alt kat + `NF`), `upper_floors`, `eave_height_m` (duvar tepesi, `SPEC["H"]`), `roof_type` + `roof` (eğim/taşma/parapet), `gf` (zemin kat yüksekliği, kat yüksekliği, `shopfront` = ön cephe deliklerinde `shop` türü var mı). Kaynak: `fam_layout.py` `FAMILIES[...]` (6 aile) ve `hero_layout.py` (old_core). Okunamayan alan `"unknown"`.
- `ind_hero` (endüstriyel salon): üreteçte `GF=0, NF=0` (kat yapısı yok) → `floors = "unknown"`; `upper_floors = 0`.
- Pivot: GLB'ler cephe çizgisinde (+Z ön). Oyun tablosu pivotu = ayak izi merkezi: `pivot_offset_m` = −(LOD0 bbox XZ merkezi); LOD0/LOD1/PROXY köşelerine EKLENİR. `footprint_m` konservatiftir (saçak/balkon dahil).
- `lod_distances_m` = `unknown` (katalog mesafeleri "working-model-not-integrated"; ölçüm A3/B-ölç işi).

## Import sözleşmesi
Tablodaki 63 hero GLB'nin `.import` dosyasında `meshes/generate_lods=false`; 14 zemin PNG'sinde `mipmaps/generate=true` (512² → 10 seviye). Kural `build_game_set.py` içinde (aksi halde çıkış 1) ve `tests/library/test_game_set.py`'de; gerçek içe aktarma denetimi: `tools/godot.sh --headless --path . --script res://tools/library/check_game_set_import.gd`. GLB/PNG baytları değişmez (onay hash'leri korunur): `artifacts/verify/t062/a0-preservation.json`.
Atlas VRAM sıkıştırması bu pakette DEĞİŞMEDİ (ölçüm + art-director kapısı A3/A5).

## Komutlar
```
python3 tools/library/build_game_set.py --write | --check
python3 -m unittest discover -s tests/library -p 'test_game_set.py'
```
Katalog, onay ya da GLB/PNG değişince `--write` yeniden çalıştırılmalı; `--check` ve testler eski tabloyu yakalar.
