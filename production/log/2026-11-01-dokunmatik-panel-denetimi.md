# 2026-11-01 · Dokunmatik (iPad) panel denetimi (ui-engineer)

Kapsam: gündem seçenek kartları, meclis oylama nedenleri, M2 sonuç paneli, yol çizim paneli (ADR-0004 ikincil profil).
Bulgu: dar yuvada (320-744 px, ui_scale 1.0/1.5) taşma/kesilme/hedef < 44 YOK. Gerçek bulgu: dokunmatikte yan yana/alt alta
düğmeler arası boşluk 4 pt (tema VBox ayırıcısı spacing/2 ve HFlow varsayılanı); `gap` tabanı 8 pt. Düzeltme:
`FlowPanel._space_for_touch` / `_button_row` (yalnız dokunmatik; masaüstü değişmedi).
Yeni testler: `tests/ui/touch_panels_test.gd` (+ `tests/ui/touch_audit.gd` ölçüm yardımcısı). Girdi: panel üstü dokunma/
sürükleme/emüle fare dünyaya geçmiyor (SubViewport push_input). Cihazda denenmedi.
