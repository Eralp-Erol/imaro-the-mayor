# Varlık kataloğu şeması (`data/library/catalog.json`) — T-052

Tek doğruluk kaynağı: oyunda ve kütüphanede bulunan her varlık burada bir kayıttır. Kit varlıkları
`assets/models/buildings/kit_manifest.json` + GLB dosyalarından **türetilir** (`tools/library/build_catalog.py`);
elle düzenlenmez. Kullanıcıya ait alanlar yeniden üretimde **korunur**.

## Sahiplik (CAN-03 ile uyumlu)

| Alan | Kim yazar | Not |
|---|---|---|
| `approval`, `approval_by`, `approval_date`, `user_note` (ve `user_*` anahtarları) | **Kullanıcı** | Betik yalnız YENİ kit kaydı için `provisional-in-use` + `approval_by: null` + bugünün tarihini yazar; var olan kaydın bu alanlarına dokunmaz. |
| `approved` / `rejected` değerleri | **Yalnız kullanıcı** | Betik bu değerleri asla üretmez; doğrulayıcı bunlar için `approval_by == "user"` ve `approval_date` ister. |
| `proposed` | Ajan | Şablon önerileri (insan, araç, yol kesiti…) bu durumla girer; GLB'si henüz olmayabilir (`glb: null`). |
| `provisional-in-use` | Sistem | Mevcut kit v0/v1: oyunda kullanılıyor, **onaylı DEĞİL**. |
| Diğer tüm alanlar | `build_catalog.py` | GLB'den ölçülür / manifestten gelir; elle değişiklik bir sonraki üretimde ezilir. |

Kit kaynaklı olmayan kayıtlar (`source.kind != "kit"`, ör. ajan önerileri) betik tarafından **olduğu gibi** korunur.
Manifestten düşen bir kit kaydı silinmez; `manifest_present: false` olur (doğrulayıcı: `provisional-in-use` ise hata,
diğerlerinde uyarı).

## Kök

`catalog_version` (1), `schema`, `generated_by`, `generated_from` (manifest yolu), `kit_version`, `palette`,
`categories[]` (`id`, `label_tr`), `entries[]`. Zaman damgası YOKTUR (idempotent çıktı).

Kategoriler: `building`, `roof_equipment`, `vegetation`, `vehicle`, `human`, `road_section`, `ground`,
`street_furniture`, `marking`.

## Kayıt (`entries[]`)

| Alan | Tür | Anlam |
|---|---|---|
| `id` | string `^[a-z][a-z0-9_]*$` | Benzersiz kimlik (kit için manifest kimliği, ör. `bld_res_mid_a_gf`). |
| `category` | enum | Yukarıdaki kategorilerden biri. |
| `family`, `variant` | string | Kit ailesi (`res_mid`…) ve varyant. |
| `era` | `old\|mid\|late\|none` | Dönem etiketi (manifestten). |
| `region` | string\|null | Bölge etiketi. **Henüz yok → `null`** (bölge karakteri art-director/kanon kararı; uydurulmaz). |
| `tags` | string[] | `era:*`, `roof:*`, `ground-floor-shop`, `landmark`. |
| `glb` | `res://…`\|null | GLB yolu; yalnız `proposed` kayıtta `null` olabilir. |
| `glb_sha256` | string | Dosyadan hesaplanır (sürüklenme tespiti). |
| `materials` | string[] | GLB'deki malzeme adları (`mat_kit`). |
| `dimensions_m` | object | GLB LOD0 `POSITION` min/max'ından ÖLÇÜLÜR: `width_x`, `depth_z`, `height_above_ground`, `foundation_skirt_depth`, `bbox_min`, `bbox_max`. (Bina GLB'lerinde zemin altı 2,5 m etek vardır; yükseklik zeminden sayılır.) |
| `triangles` | object | `LOD0`, `LOD1`, `PROXY` (GLB'den sayılır; yoksa `null`). |
| `palette_rows` | object | Manifestteki duvar/çatı/aksan palet satırları (bilgi amaçlı). |
| `source` | object | `kind` (`kit`\|`template`\|…), `generator` (üreteç betiği, diskte olmalı), `manifest`, `rebuild` (yeniden üretim komutu), `spec`. |
| `manifest_present` | bool | Kit kaydının manifestte hâlâ olup olmadığı (türetilir). |
| `approval` | enum | `proposed\|approved\|rejected\|provisional-in-use`. |
| `approval_by` | `"user"`\|null | `approved/rejected` için zorunlu `"user"`; diğerlerinde `null`. |
| `approval_date` | `YYYY-AA-GG`\|null | Durumun işaretlendiği tarih. |
| `user_note` | string | Kullanıcı notu (boş başlar). |

## Doğrulayıcı kuralları (`tools/library/validate_catalog.py`, testler `tests/library/`)

Zorunlu alanlar · enum değerleri · çift kimlik · eksik GLB / üreteç dosyası · manifestteki her modül katalogda ·
katalog değerleri GLB'den yeniden ölçülenle birebir (üçgen, boyut, sha256) · manifest üçgen sayısı = GLB · manifest
bütçeleri (`max_lod0_tris`, `proxy_max_tris`) · `approved/rejected` ⇒ `approval_by == "user"` + tarih · `approval_by`
diğer durumlarda `null`.

## İş akışı

```
python3 tools/library/build_catalog.py --write     # manifest/GLB değişince
python3 tools/library/validate_catalog.py          # doğrula
tools/library/render_sheets.sh                     # sayfaları yeniden üret
```

## Hero LOD zinciri (T-056; yalnız kütüphane)

Hero kayıtlarında isteğe bağlı `lod_chain` bulunur. `levels.LOD0|LOD1|PROXY`,
`glb`, `sha256`, gerçek `triangles`, `bbox_min/max`, `materials` içerir. Kök
`triangles` bu ölçümlerle eşleşir. `status: proposed`, mevcut bina onayını yeni
LOD'lara taşımaz. `distances_m` 100/300 m çalışma değeridir; oyun entegrasyonu değildir.
`atlas` LOD1'in kaynak dokusunu hash ile tanımlar. `proxy_atlas`, özgün LOD0'ın
ışıksız ön ortografik albedo görüntüsünden, yan/arka kaynak tile korunarak aynı UV düzeninde üretilmiş
256×256 PNG'yi ve kaynak GLB hash'ini izler; yeni doku/LOD kullanıcı onayı değildir.
Üreteç `art/blender/hero/build_lods.py`; ölçüm/güncelleme
`python3 tools/library/hero_lods.py --write`, bayatlık kontrolü `--check`.
Ana katalog doğrulayıcı, zincirin dosya/hash/üçgen/doku sürüklenmesini ve bütçeyi
(LOD1 ≤800, proxy ≤80 üçgen) denetler. `approval*`, `user_note`, `user_*` korunur.
