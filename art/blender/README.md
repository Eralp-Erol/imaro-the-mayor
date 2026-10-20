# art/blender - Blender asset pipeline

Uretim yolu: **headless, deterministik bpy script'leri** (`generators/*.py`) -> `.glb`. MCP koprusu
(`tools/blender/`) yalnizca interaktif kesif icindir; tekrarlanabilir varlik MCP'den cikmaz.

Calistirma (ornek):
`/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/generators/lowpoly_block.py -- --floors 5 --width 14 --depth 10 --out <yol>.glb`

## Konvansiyonlar
- Birim metre (scale_length 1.0). Blender Z-up; glTF exporter Y-up'a cevirir (`export_yup=True`).
- Origin = zemin ortasi (x/y ortali, z=0 zemin). Transformlar uygulanmis (loc 0, rot 0, scale 1).
- Adlandirma: nesne/mesh `bld_<ad>` (ornek `bld_block_5f`); dosya `bld_<ad>.glb`. Malzeme `mat_<ad>`.
- Malzeme: duz, mat (roughness 1, metallic 0, specular 0), doku yok, UV yok (varsayilan).
- Alt yuz yok (kamera asla altini gormez); tek mesh, malzeme basina bir primitive.
- Uretim kodu rastgelelik icermez; ayni arguman -> ayni byte (glb hash'i sabit; 3 kosuda dogrulandi).
- Ucgen butcesi (rehber): mid-rise blok (district LOD) <= 600 tri; tek bina yakin LOD <= 2000 tri.
  `lowpoly_block.py`: kat basina 36 + cati 28 tri (5 kat = 208 tri).
- Cikti Godot'ya `res://` altinda kopyalanip import edilir; kaynak `.blend` varsa `art/blender/src/` (henuz yok).

## Dogrulama
`experiments/asset-pipeline-smoke/` Godot projesi: `check_import.gd` (tri sayisi, AABB, malzeme) ve `capture.gd` (PNG).
