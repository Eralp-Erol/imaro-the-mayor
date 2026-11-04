class_name HudHelp
extends RefCounted
## Oynanabilir sahnenin alt yardım metni (T-047, ölçüt 3). Saf hesap: oyuncuya yalnız kısa kontrol yardımı + sim günü;
## geliştirici notu ve sayaçlar yalnız `--dev-notes` ile. Konum: HUD'un boş harita dikdörtgeni (`HudRoot.free_map_rect`)
## içinde, sol-altta; araç çubuğu ve paneller o dikdörtgenin dışında olduğundan çakışma kurgusal olarak yoktur.

const MAX_WIDTH := 640.0
const MARGIN := 12.0


## `dev_lines`: `--dev-notes` ile gösterilecek geliştirici satırları (oyuncu modunda yok sayılır).
## `touch`: dokunmatik profilde klavye/fare yardımı gösterilmez (yalnız sim günü).
static func status_text(sim_day: int, dev_notes: bool, dev_lines: String = "", touch: bool = false) -> String:
	var day := UiText.t(&"hud.sim_day", {"day": sim_day})
	var text := day if touch else "%s\n%s" % [UiText.t(&"hud.controls_help"), day]
	if dev_notes and dev_lines != "":
		text += "\n" + dev_lines
	return text


## Yardım etiketinin yeri: boş harita dikdörtgeninin sol-altı. Genişlik dikdörtgene sığar (dar pencerede satır sarar).
static func status_rect(free_map: Rect2, height: float) -> Rect2:
	var width := minf(MAX_WIDTH, maxf(0.0, free_map.size.x - 2.0 * MARGIN))
	return Rect2(Vector2(free_map.position.x + MARGIN, free_map.end.y - MARGIN - height), Vector2(width, height))
