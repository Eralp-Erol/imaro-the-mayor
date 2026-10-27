# T-059 bağımsız QA incelemesi (ölçüt 1,2,3,6,7; görsel 4/5 art-director)

Dal agent/handover-imaro-m01-349562fb, HEAD e279f6f, çalışma ağacı temiz (yalnız untracked artifacts/library, tmp). Donanım: macOS Darwin 24.6, Godot 4.7.2.stable, Python 3.9.12. Kod/asset DEĞİŞTİRİLMEDİ; rebuild.sh ÇALIŞTIRILMADI.

## Kriter tablosu
| # | Ölçüt | Sonuç | Kanıt |
|---|---|---|---|
| 1a | Deterministik üreteç, hash eşitliği | PASS (kayıttan) / Blender üretimi UNVERIFIED | artifacts/verify/t059/determinism.json: 15 dosya run1==run2 ve run2 == bugünkü ağaç (kendi hash'lerimle). Blender'ı kendim koşmadım. |
| 1b | Gerçek metre/origin, malzeme/UV | PASS | Kendi glTF ayrıştırıcım: 12 GLB yükseklik 1.7500, min y 0.0000, 1 primitive/1 malzeme/1 image, UV [0,1] |
| 1c | Eski bina/zemin/LOD/kullanıcı alanı değişmez | PASS | `git diff 51206c6 e279f6f --name-status`: yalnız 5 M (SCHEMA.md, catalog.json, test_furniture_catalog.py, build_gallery.py, validate_catalog.py), geri kalan A. Kanon klasörü diff 0 satır. 99 eski kayıt git show 51206c6 ile birebir eşit, göreli sıra korunmuş, üst düzey alanlar eşit |
| 2 | LOD0<=900, LOD1<=100, cull | PASS | 198/98, 654/98, 122/66 (kendi sayımım = katalog); LOD1 bbox LOD0 zarfında (aşım 0.0 m); proxy dosyası yok; distances_m status=working-model-not-integrated |
| 2b | Yüz/logo/yazı/emission/ışık/kültürel giyim yok | PASS | GLB JSON: emissive yok, KHR_lights yok (yalnız KHR_materials_specular=0), opak, doubleSided=false; atlas PNG açıldı: 8 düz karo, desen/yazı/sembol yok; sayfalar (B nötr, A geniş, C nötr) açıldı: yüz boş, logo/yazı yok |
| 3 | Katalog kimlik/category/kind/proposed, drift reddi | PASS | 6 benzersiz kimlik, category=human, kind=hero_human, approval=proposed, approval_by/date null, user_note "", PROXY yok; sha256 12 GLB+atlas+layout katalogla eşit; tmp mutasyonları aşağıda |
| 6 | Python/katalog/Godot import/lint | PASS | Aşağıdaki komutlar |
| 7 | Ölçülen/hesaplanan/test edilmemiş ayrımı | PASS | design/library/human-hero.md "Riskler / test edilmedi" bölümü var; verify.sh KOŞULMADI açık yazılı; Q-018 seçilmiş gibi yazılmamış |

## Koşular (komut -> çıkış kodu)
- `python3 -m unittest discover -s tests/library -p 'test_*.py' -q` -> 0 (96 test OK; test_human_catalog 23/23)
- `human|furniture|vegetation_catalog.py --check`, `hero_lods.py --check`, `build_catalog.py --check` -> hepsi 0 ("105 entries, up to date")
- `python3 -I tools/library/validate_catalog.py` -> 0 ("105 entries, 0 errors, 0 warnings")
- `tools/godot.sh --headless --path . --script res://tools/library/check_human_import.gd` -> 0: `HUMAN_IMPORT_OK meshes=12 shared_texture=1 opaque=true single_sided=true mipmaps=true generate_lods=false shader_materials=0 post_import_scripts=0 casts_and_receives_shadow=true chain=LOD0/LOD1 proxy=absent emission=none`
- Negatif: hum_hero_pawn_broad_a_lod1.glb.import'ta geçici generate_lods=true -> çıkış 1, `ERROR: hum_hero_pawn_broad_a LOD1: meshes/generate_lods must be false`; `git checkout --` ile geri alındı; `git diff --stat` boş.
- `--check-only` human_lab.gd ve check_human_import.gd -> 0.
- Değişen dosyaların hepsi art/blender/human, assets/hero/human, design/library, tools/library, tests/library, data/library altında; sim/render/input dosyası yok.

## Korunanlar / test gevşetme değerlendirmesi
tests/library/test_furniture_catalog.py diff'i (2 değişiklik):
- (a) `81 == len(entries)-18` -> `81 == len(entries not in {hero_furniture, hero_vegetation, hero_human})`: aynı değişmez (81 eski kit kaydı), sabit kayması yerine tür filtresi. Zayıflama DEĞİL.
- (b) `set(ids)-old == new` -> `set(ids)-old-human == new`: furniture testi hâlâ "91 eski kimlik korunur, çakışmaz, eklenenler tam olarak fur_hero_*" der. İnsan kümesi katalogdan türetildiği için bu testte tek başına bağlı değil, ama test_human_catalog 6 insan + 99 gömülü eski kimlik listesini (PRE_T059_IDS) ayrıca pinler. MEŞRU.
- Açık not (düşük, önceden var olan boşluk): hiçbir commit'li test eski 99 kaydın İÇERİĞİNİ baz çizgiye karşı karşılaştırmaz (yalnız kimlik). İçerik koruması gitignored artifacts/verify/t059/pre.json + benim git-show karşılaştırmama dayanır.
Diğer M dosyaları: validate_catalog.py (+1 import, +1 işleyici eşlemesi), build_gallery.py (insan etiketleri), SCHEMA.md (ek bölüm): gerekçeli, yan etkisiz.

## Tmp kopyada bağımsız mutasyonlar
REDDEDİLDİ: GLB'ye emissive (katalog bayat), doubleSided=true, ikinci image, yükseklik x1.1, atlas RGBA, approval=approved (approval_by yok), çift kimlik, category/source eksik, distances status=integrated; ayrıca testlerde: LOD1>cap, LOD1 zarf dışı, post-import script, proxy kalıntısı, bozuk/eksik GLB, atlas bayt değişimi.
KABUL EDİLDİ (tespit yok): emissive + katalog yeniden üretildi; KHR_lights eklendi + yeniden üretildi; notes='üniformalı logo'; source.kind='bogus'. (approved+user+date kabul = tasarım gereği kullanıcıya ait.)

## Bulgular (hepsi düşük, engelleyici yok)
1. tools/library/human_catalog.py:127-157: GLB'ye emissiveFactor veya KHR_lights_punctual eklenip katalog yeniden üretilirse Python doğrulayıcı reddetmez. Emission'ı Godot denetimi (check_human_import.gd:50) yakalar; KHR_lights için denetim yok. Şu anki 12 GLB temiz (ölçtüm). Öneri: Python tarafına emissive/extensions allow-list.
2. human_catalog.py:112: yasak sözcük taraması yalnız label_tr+user_note; `notes` alanı taranmaz. Etiketler allow-list'li; risk düşük.
3. tools/library/validate_catalog.py:98: bilinmeyen source.kind sessizce hero_lods işleyicisine düşer ve [] döner (kind='bogus' hem insan hem eski fur_/bld_ kayıtlarında kabul). Önceden var olan davranış, T-059 getirmedi.
4. tools/library/human_preservation.py:2-3 docstring `furniture_preservation.py` diyor (kopyala-yapıştır). Kozmetik.
5. Sayfa gözlemi (art kapısına not): C faset ön görünümde ceket eteğinde bir yanda koyu çentik (human-hero.md zaten "bilinen kusur" diyor); C LOD1 = B LOD1 (98 üçgen) belgelenmiş.
6. index.json'daki 48 ham kare yolu diskte VAR, ama artifacts/screenshots/captures/ gitignored: temiz checkout'ta yok (sayfa PNG'leri ise commit'li, 14 dosya).

## Kontak sayfaları (ölçüt 8)
index.json: 6 kimlik, 48 ham kare yolu mevcut, boyut/üçgen/kimlik katalogla eşit (6/6). Açılan: hum_hero_block_neutral_a, hum_hero_pawn_broad_a, hum_hero_facet_neutral_a. Başlıklar gerçek kimlik, ölçü (g x d x y) ve LOD0/LOD1 üçgen taşıyor; ön/yan/arka/üst/3-4/LOD1 + 12 m + 60 m kareleri gerçek Godot çıktısı, "ÖNERİ (seçilmedi)".

## Test edilmedi / doğrulanmadı
Blender yeniden üretimi (rebuild.sh yasak), tools/verify.sh quick/full (kapsam dışı), sanat kalitesi (ölçüt 4/5, art-director), hero bina bağlam sahneleri, gerçek şehir/hedef cihaz performansı, kalabalık draw call'u.

## Verdict
T-059 ölçüt 1,2,3,6,7: PASS (kayıtlı üretim determinizmi dışında bağımsız ölçüldü). Engelleyici bulgu yok.
