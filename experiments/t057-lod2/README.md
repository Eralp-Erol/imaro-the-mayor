# T-057 LOD2 deneyi (Teknik karar 4, 4.2/4.3) - SONUC: KAZANC YOK (P4 BASARISIZ), sanat PASS yok

Yetki: `production/qa/T-057-technical-review.md` Teknik karar 4. Yalniz technical-artist asamasi (4.6 madde 1). Godot
calistirilmadi, `.import` uretilmedi, oyuna baglanmadi, commit atilmadi. Tek cinar, tek uretim; sabitler
(17 bakis, 24 px/m, alpha 0.45, 0.98 / 0.90 / 0.95) degistirilmedi, ayar turu yapilmadi.

## Tarif (calistirilan)
- `uv run --with pillow==11.3.0 python -I experiments/t057-lod2/build.py` (saf Python; numpy yok) ->
  `assets/hero/vegetation/lod2_experiment/veg_hero_plane_a_lod2.glb` + `experiments/t057-lod2/provenance.json`.
- Ayristirma: tam float32 konum eslemesiyle kaynaklama, bagli bilesenler; 64 yaprak x2 tri + 20 odun x8 tri (aksi halde SpecStop, cikis 2).
  Segment yonu halka yaricapindan (buyuk = proksimal); ebeveyn <=1 mm halka merkezi eslesmesi; kart -> centroid'e en yakin dal distal ucu (esitlikte GLB sirasi).
- Cikarilamaz: yere degen gövde (1), en yuksek dal tabaninin (z=5.3 m Blender) altindaki proksimal gövde (2), dalin gövdeye bagli ilk segmenti (8), distal cocugu kalan segment. Cikarilabilir: 64 kart + 8 dal ucu segmenti + 1 ust gövde segmenti.
- Raster: ortografik ID z-buffer, 24 px/m, 17 bakis (8 azimut x {12,40 derece} + tepe), tabana en yakin texel alpha >= 0.45 (bayt >= 115).
- Acgozlu: en dusuk puanli cikarilabilir oge (esitlikte GLB sirasi), her adimdan sonra puan yeniden; sonraki cikarma (a) toplam kapsama >=0.98, (b) kume kart birlesim maskesi >=0.90, (c) onde gorunen odun >=0.95 x LOD1 kosullarindan birini bozacaksa durur. Karsilastirmalar tam sayi (a*100 >= b*98).
- Yazici: POSITION/NORMAL/TEXCOORD_0 bayt kopyasi, index yeniden numaralanir, materyal JSON ayni, URI `../vegetation_atlas.png`.

## Gercek olcumler
- LOD1 288 tri / 576 vertex / 21624 bayt. **LOD2 270 tri** / 540 vertex / 20368 bayt (sha256 `78eb5606...dca6`). Tavan 172.
- Cikarilan 3 oge (sirayla): eleman 75 (dal ucu segmenti, kume 7, puan 214), eleman 7 (yaprak karti, kume 0, puan 393), eleman 15 (dal ucu segmenti, kume 1, puan 598) -> 18 tri.
- Durma: sonraki aday eleman 55 (dal ucu, puan 792) kosul (c)'yi bozar: tepe bakisinda (0,90) onde gorunen odun 339 -> 316 px (0.932 < 0.95).
- Alpha oncesi fragment alani (17 bakis toplami): LOD1 2 182 145 px (3788.4 m2), LOD2 2 156 004 px (3743.1 m2), **oran 0.988** (kapi <= 0.80).
- Bakis basina LOD2/LOD1 (audit bagimsiz yeniden hesap, build ile 0 px fark): kapsama min 0.9951 (0,12); odun oranlari 0.9662 (225,12) .. 1.0; kume min orani 0.909 (315,12). Hepsi kosullari saglar (tam tablo `audit.json` P3.views).
- Bilgi amacli on yuz (0,12) dogrusal albedo ortalamasi (kapi degil): LOD1 (0.1339, 0.1837, 0.0712), LOD2 (0.1335, 0.1838, 0.0711).
- Hash'ler: LOD1 `2e5c465e...9d6a`, atlas `b01a6a07...fb79`, atlas_layout `37be1a47...bccb`, provenance `58666547...7628` (tam degerler provenance/audit.json).

## Kapilar
| Kapi | Sonuc |
|---|---|
| P1 64+20 bilesen | GECTI |
| P2 her LOD2 ucgeni LOD1'de (konum, normal, UV) bit-esit, sira/materyal/URI | GECTI |
| P3 kapsama kosullari bagimsiz yeniden hesapta | GECTI |
| P4 tri <=172 ve fragment <=0.80 x LOD1 | **BASARISIZ** (270 > 172; 0.988 > 0.80) |
| P5 iki tam uretim bayt-esit GLB+provenance | GECTI |
| N1 vertex 1e-4 m kaydir -> P2 duser | GECTI (cikis 1) |
| N2 en cok gorunen kart (eleman 27) sil -> P3 duser | GECTI (cikis 1) |

P4 basarisiz oldugu icin Teknik karar 4 gerekce 4.3 uyarinca "LOD2 kazanc yok" olarak kayitlidir; Godot importu/render/K1-K6/sanat kapisina gecilmez. Yol LOD1 uzatmaya doner (4.2 kontrol yolu). Baska esik/bakis/parametre denenmedi.

## Dogrulanan / varsayilan / calistirilmayan
- Dogrulanan (komutla): yukaridaki P1-P5, N1, N2 (`uv run --with pillow==11.3.0 python -I experiments/t057-lod2/audit.py`, cikis 1 cunku P4 basarisiz).
- Varsayim/modelleme: alpha-gecen fragmanlar derinlik/ID yazar, gecmeyenler ne kapsar ne ortter (gercek alpha-scissor materyali gibi); mip, MSAA, isik, Godot ornekleme modellenmedi; ortografik bakislar oyun kamerasi degil.
- Calistirilmayan: Godot import (P6/N3), lab, K1-K6 kareleri, sanat degerlendirmesi, hareketli test, `preservation.json` (godot-engineer asamasi). Sanat PASS iddiasi yok.

## Sinirlamalar ve spesifikasyon belirsizlikleri (sessizce yorumlanmadi)
1. Yeni GLB tek duzensizlik: tube halka dikisi (seam) bir halka konumunu ~1e-16 farkla iki kez uretir; tam esitlik kaynagi bilesenleri bozmaz (P1 gecer) ama halka merkezi/yaricapi hesabinda halka UV satiri (v) ile 8 vertex kaydi uzerinden ortalama alindi (spec "halka yaricapi" der, halkanin nasil bulundugunu belirtmez).
2. Kume boyutlari 8,7,8,8,7,9,8,9 (en yakin dal ucu kuralina harfiyen uyuldu); spec 4.1-B "8 kume x 8 kart" der.
3. "Durulur" ilk (en dusuk puanli) adayin ihlalinde durmak olarak uygulandi (diger adaya gecilmedi). Kosul (c) tepe bakista yalnizca 339 px odun oldugundan 17 px toleransla cok sikidir; bu sonucu belirleyen kosuldur.
4. Cikarilan odun segmentlerinde ona atanmis kartlar kalir (spec yalniz "distal cocuk" kuralini verir); sonucu etkilemedi (cikarilan dal ucu kartlari kapsiyordu, gorsel degerlendirme yapilmadi).
5. Kume atamasi audit'te provenance'tan okunur (yalniz kapsama yeniden hesabi bagimsizdir; kume bolunmesi build'in turevidir).
6. Spec 4.2 beklentisi (gizli odun ~64-80 tri) gerceklesmedi: olculen azaltma 18 tri.
7. Node/mesh adlari `..._lod1` -> `..._lod2` yapildi (materyal JSON ayni).

## Dosyalar
`build.py`, `audit.py`, `provenance.json`, `audit.json`, `negative-results.json`, `determinism.json`, bu README; GLB `assets/hero/vegetation/lod2_experiment/veg_hero_plane_a_lod2.glb`.
