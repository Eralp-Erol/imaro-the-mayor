# 2026-11-05 · ui-engineer · iPad çekmecesi diğer şehri örten panellere (D-021 genişletme)
Kapsam taraması (`hud.open_panel` çağrıları; dokunmatikte şehri yandan/alttan örten gerçek paneller):
- Çekmeceye BAĞLANDI: meclis, bütçe, gündem (kamulaştırma yanıt kartları dahil), politika (`DecisionPanels`), sonuç + nedensellik (`M2Results`), denetçi (`InspectorHost`), yol çizimi + kamulaştırma onayı (`RoadDrawController`). İmar zaten bağlıydı.
- Bağlanmadı: yalnız dev galerileri (ui_lab "actors"/"states"); oyuncu paneli değil. Bekleme listesi ayrı panel değil, gündem/sonuç içindeki satır; panel olarak bağlı.
- Mekanizma aynı (`DrawerModel`/`DrawerGrip`/`PanelShell`): `open_panel(..., true)` bayrağı; kapalı/yarı/tam, ok düğmeleri + parmakla sürükleme, harita dokunuşu çekmece dışında. Masaüstü: bayrak etkisiz, yan panel aynen.
- Yeni panel açılınca konum YARI'ya döner (panel değişince kalıcı değil).
- Eylem düğmeleri: yalnız imar yapışık altlığı kullanıyor (Planı sun); diğer panellerin düğmeleri gövdede, YARI'da kaydırma gerekebilir, TAM'da hepsi görünür.
- Taste: yarı yükseklik oranı -> Q-037 (veri: `drawer_frac_half`, 0,62).
- Kanıt: `tests/ui/drawer_test.gd` genişletildi; pencereli kareler `artifacts/qa/cekmece-paneller/`. Fiziksel iPad denenmedi.
- Not: yatay iPad'de denetçi/yol gibi küçük paneller eskiden sağda dar şerit (şehir açık) idi; çekmecede alttan yarı yükseklik kaplar. Bu bir ödünleşimdir, Q-037 seçenek C bunu çözer.
- Doğrulama: `verify quick` 295/313 suite, 0 başarısız, 1200 sn zaman aşımına uğradı (paralel `full` yükü; quick FAIL satırı bu). `drawer_test` 33 + `drawer_panels_test` 7 geçti. gdlint temiz.
