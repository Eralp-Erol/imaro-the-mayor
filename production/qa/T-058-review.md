# T-058 bağımsız QA incelemesi (ölçüt 1, 2, 3, 6, 7)

Tarih 2026-10-27 · HEAD e090160 · dal agent/handover-imaro-m01-349562fb · Godot 4.7.2.stable · macOS (Darwin 24.6.0).
Kod/asset değiştirilmedi; commit/push yok. Ölçüt 4/5 (görsel) art-director'a ait.
Bu koşuda yalnız kendi başlattığım süreçler kullanıldı. Çalışma ağacı farkı başlangıçla aynı: yalnız `artifacts/verify/full-latest.json` (QA öncesi var) ve izlenmeyen `artifacts/library/`, `tmp/`.

## Tablo

| # | Kontrol | Sonuç | Kanıt (bu oturumda koşuldu) |
|---|---|---|---|
| 1 | `python3 -m unittest discover -s tests/library -p 'test_*.py'` | PASS | 73 test OK, çıkış 0 (test_furniture_catalog.py: 20 test) |
| 1 | `furniture_catalog / vegetation_catalog / hero_lods / build_catalog --check` | PASS | dördü de çıkış 0; "furniture proposals 8; measured LODs 16", "catalog: 99 entries, up to date" |
| 1 | `validate_catalog.py` | PASS | "catalog: 99 entries, 0 errors, 0 warnings", çıkış 0 |
| 2 | Gerçek Godot import denetimi `tools/godot.sh --headless --path . --script res://tools/library/check_furniture_import.gd` | PASS | çıkış 0, `FURNITURE_IMPORT_OK meshes=16 shared_texture=1 opaque=true single_sided=true mipmaps=true generate_lods=false shader_materials=0 post_import_scripts=0 casts_and_receives_shadow=true chain=LOD0/LOD1 proxy=absent emission=none` |
| 2 | Bağımsız negatif: `fur_hero_bin_a_lod1.glb.import` içinde geçici `generate_lods=true` | PASS (reddedildi) | çıkış 1, `ERROR: fur_hero_bin_a LOD1: meshes/generate_lods must be false` (check_furniture_import.gd:126). `git checkout --` ile geri alındı; `git diff --stat -- assets` boş, dosyada `generate_lods=false` |
| 3 | 16 GLB'yi kendi glTF ayrıştırıcımla ölçtüm (ikili parça, düğüm dönüşümleri dahil; katalog kodundan bağımsız) | PASS | Üçgen 16/16 katalogla eşit. Bütçe: LOD0 138..652 (≤1600), LOD1 44..158 (≤240). bbox katalogla ≤0.002 m içinde. min Y 0.0000 (ground-origin, 16/16). Tek mesh/primitive, 1 materyal `mat_furniture_atlas`, 1 harici görsel `furniture_atlas.png`. GLB dosya sha256 = katalog `sha256` (16/16). Boyutlar metre: bank 1.80×0.575×0.801, çöp 0.5×0.5×0.9, direk 1.67×0.28×8.002, bollard 0.2×0.2×0.87, bisiklet 0.81×1.91×0.861, durak 5.0×1.6×2.6, saksı 1.2×1.2×1.34, kiosk 2.4×2.0×2.68 |
| 3 | Atlas hash/layout hash katalog kayıtlarıyla | PASS | 8/8 kayıtta `atlas.sha256` ve `layout_sha256` diskteki dosyalarla eşit |
| 4 | 91 eski kayıt 6908d03 ile eşit | PASS | `git show 6908d03:data/library/catalog.json` ile karşılaştırıldı: 91/91 kayıt eşit, sıra korunmuş, üst düzey alanlar eşit, kopya kimlik 0 |
| 4 | Mevcut dosya değişiklikleri (`git diff 6908d03 e090160 --name-status`) | PASS | Eklenmeyen (M) yalnız 4 dosya: `data/library/SCHEMA.md` (ek bölüm), `data/library/catalog.json`, `tools/library/build_gallery.py` (+3 satır), `tools/library/validate_catalog.py` (+1 satır dispatch). Eski bina/bitki/zemin/model asset'inde M yok. `design/foundation` değişikliği 0. Furniture dışı eklenen yol yok |
| 5 | 8 donatı kaydı | PASS | Benzersiz kimlik, `category=street_furniture`, `source.kind=hero_furniture`, `approval=proposed`, `approval_by/date=None`, `user_note=""`, `lod_chain.status=proposed`, `distances_m.status=working-model-not-integrated`, proxy yok (8/8) |
| 5 | Negatif testlerin anlamlılığı | PASS (okuma + el yapımı girdi) | Kodu okudum: `validate_chain` beklenen kaydı gerçek dosyadan yeniden ölçüp karşılaştırıyor (hash/bbox/üçgen/atlas drift), gerçek kesik/bozuk/eksik GLB, gerçek 652 üçgenli GLB'nin LOD1 yerine konması, gerçek `.import` metin düzenlemesi (generate_lods/post-import), proxy dosyası. Kendi geçici girdilerim (tmp kopya, repo dokunulmadı): GLB'de 1 bayt çevirme → `glb_sha256 drift`; materyal adı değişimi → "exactly one shared mat_furniture_atlas"; atlas uri değişimi → "texture must be the external shared furniture_atlas.png"; katalogda LOD1 üçgen=999 → reddedildi; temiz kayıt → `[]` |
| 6 | Yasak içerik | PASS | GLB materyal JSON'u: 16/16 emissive/KHR_materials_emissive_strength/ışık uzantısı yok, alphaMode yok (opak), doubleSided=false, metallic 0, specular 0. Atlas PNG açıldı (1024², RGB): 16 düz/desenli dokü karosu, metin/logo/yazı görülmedi. Godot denetimi emission'ı reddediyor. Gözlem: "kiosk_green", petrol ve krem-turkuaz tente renkleri seçilmiş çalışma değeri; marka değil, Q-018 kapsamında (belgede belirtilmiş) |
| 7 | Determinizm kaydı | PASS (belge tutarlılığı; yeniden çalıştırılmadı) | `artifacts/verify/t058/determinism.json`: iki koşu 19 dosya (16 GLB + atlas + layout + katalog), identical=true. Kayıtlı run2 hash'leri şu an diskteki dosyalarla eşit (sapan 0). `preservation.json`: 91/91 kayıt, 216 korunan dosya eşit, `pass:true`; bu bulgu benim bağımsız git karşılaştırmamla da uyumlu. Blender yeniden üretimi bu oturumda doğrulanmadı |
| 8 | Kontak sayfaları | PASS (düşük bulgularla) | `index.json` 64 ham kare yolu diskte, 8 sayfa + 3 bağlam PNG diskte. Açılan sayfalar: kiosk, bisiklet demiri, sokak direği + context-scale: başlıkta gerçek kimlik, ölçü (g×d×y), üçgen LOD0/LOD1, sha8 (katalogla eşit), mesafe, "Işık/yazı/logo yok · proposed · Q-018 açık". `furniture-hero.md` tablosu (üçgen, mesafe, sha8, ölçü) 8/8 katalogla eşit; "73 test / 20 yeni" iddiası doğru. Eski/yanlış iddia bulunmadı |
| 6/ölçüt metni | `gdlint`, `capture` yeniden koşusu, `tools/verify.sh quick/full`, oyun smoke, performans/draw-call | UNVERIFIED | Koşmadım (kapsam dışı; belge de koşulmadı diyor) |

## Bulgular (engelleyici yok)

1. Düşük — `design/library/sheets/furniture-hero/fur_hero_lamp_street_a.png` sağ alt panelinde ham Python çıktısı: "Şablon: fur_lamp_street_a [1.5, None, 8.0]". Kaynak `tools/library/render_furniture_sheets.py` (template_size_m listesi doğrudan basılıyor; satır ~57 çevresi).
2. Düşük — `fur_hero_bike_rack_a.png` panelinde "Ölçü: working-value (no template row; 3 hoops" metni kesik; `furniture_catalog.py` `TEMPLATES['bike_rack']['size_status']` uzun İngilizce dizgesi sayfada yarım basılıyor.
3. Düşük — `tests/library/test_furniture_catalog.py` son test (`test_ids_unique_new_and_follow_readme_naming`): `artifacts/verify/t058/pre.json` yoksa `old={}` olur ve "yeni kimlik eskilerle çakışmıyor" iddiası boşa geçer. `artifacts/verify/*` .gitignore'da (.gitignore:27), yani temiz checkout'ta bu kontrol anlamsızdır. Eski 91 kimlik kontrolü kalıcı testte değil, yalnız `furniture_preservation.py` çıktısında. Öneri: eski kimlik listesini teste gömmek.
4. Düşük (izlenebilirlik) — `index.json` ham kare yolları `artifacts/screenshots/captures/` altında (.gitignore:9, izlenmiyor); determinism/preservation JSON'ları da `artifacts/verify/` altında (ignore). Temiz checkout'ta yollar boş kalır; kontak sayfa PNG'leri ve belge izleniyor, yani görsel kanıt korunuyor.
5. Bilgi — `furniture-hero.md`: direk kolu "≈1,5 (başlık dahil 1,53)" deniyor; ölçülen toplam genişlik 1.67 m (şablon 1.5). Çelişki değil (kaide/kapak ve armatür payı), ama tablodaki 1,67 ile metin arasındaki fark açıklanmamış.
6. Bilgi — Belgenin kendi yazdığı sanat uyarıları (bollard/çöp kutusu/bisiklet demiri uzaktan düz renk, cam koyu, 100 m'de bollard/çöp neredeyse görünmez, cull mesafesi ölçülmedi) bağımsız olarak context-scale ve sayfa kırpımlarında tutarlı gözlendi; karar art-director'a.

## Doğrulanan / varsayılan / test edilmemiş

- Doğrulanan: yukarıdaki tüm PASS satırları (bu oturumda koşuldu, çıkış kodları ve çıktılar alındı).
- Varsayılan: Blender yeniden üretiminin bit-aynılığı (kayıtlı JSON diskle tutarlı; yeniden çalıştırma yasaktı).
- Test edilmeyen: `tools/verify.sh`, gdlint/yeni capture, oyun içi LOD geçişi, draw-call/frame time, hedef cihaz bütçesi, ölçüt 4/5 sanat kararı, Q-018 kararları.

## Hüküm

Ölçüt 1, 2, 3, 6, 7 için kanıtlanabilir kısım PASS; engelleyici bulgu yok. Düşük bulgular 1-4 teslimi durdurmaz (sayfa metni, boş geçebilen bir test, izlenemeyen artefakt yolu).
