# 2026-11-05 · ui-engineer · iPad alttan çekmece (D-021)
- Dokunmatikte imar paneli alttan çekmece: KAPALI/YARI/TAM, parmakla sürükle + ok düğmeleri, güvenli alan içinde, harita dokunuşu çekmece dışında çalışır (gerçek `InputEventScreenTouch` ile parsel ekleme 3->4 denendi).
- Yeni: `src/ui/components/drawer_model.gd`, `drawer_grip.gd`; değişen: `panel_shell.gd`, `hud_layout.gd`, `hud_root.gd`, `flow_panel.gd`, `zoning_flow_panel.gd`, `decision_panels.gd`, `ui_tokens.json`, `strings.tr.json`. Masaüstü yolu değişmedi.
- Diğer karar panelleri bağlanmadı (bkz. B-100).
- Kanıt: `tests/ui/drawer_test.gd` (16 test), pencereli kareler `artifacts/qa/ipad-cekmece/` (git dışı). Fiziksel iPad denenmedi.
