class_name ExpropriationText
extends RefCounted
## Kamulaştırma (T-042b, D-011, ADR-0005 Ek F) metin yardımcısı: SAF, düğüm yok. Sayılar YALNIZ sim'in
## `CommandResult.args` ve olay args'ından gelir (`taken_*`, `displaced_households`, `nearby_*`, `restored_*`);
## burada hesap ya da tahmin yoktur. Bedel: sim'de kurulu değil (Q-017/T-014, Q-003): "Bedel: henüz
## kurulmadı", para simgesi/sayısı yok.
## T-065 (D-016): yeniden iskân politikası AÇIKKEN sim önizleme/olay args'ına `resettlement_applied`,
## `rehoused_households`, `unplaced_households`, `resettlement_cost` ekler; kapalıyken bu anahtarlar YOKTUR ve metin
## bugünküyle aynıdır. Bedel GÖSTERGEDİR (para kısıtı değil, Q-003/T-014).
## Teklif = `crosses_parcels` retinin args'ı kamulaştırma önizleme anahtarlarını (`taken_parcels` > 0) taşır;
## kamulaştırma kapalıysa ya da dünya sunmuyorsa bu anahtarlar YOKTUR ve "kamulaştırma henüz yok" metni kalır.

const CROSSES_PARCELS := &"public_work.reject.crosses_parcels"
const CROSSES_PARCELS_OFFER := &"public_work.reject.crosses_parcels_offer"
const EVENT_EXPROPRIATED := &"event.road.expropriated"
const EVENT_RESTORED := &"event.road.restored"


## `crosses_parcels` reddi sim'in kamulaştırma teklifini taşıyor mu?
static func is_offer(reason_key: StringName, args: Dictionary) -> bool:
	return reason_key == CROSSES_PARCELS and has_impact(args)


## Argümanlar alınacak arsa bildiriyor mu (teklif ya da kamulaştırmalı geçerli önizleme)?
static func has_impact(args: Dictionary) -> bool:
	return int(args.get("taken_parcels", 0)) > 0


## Yıkım/yerinden edilme/proje kaybı var mı? Varsa onay ayrıca ve açıkça istenir.
static func demolishes(args: Dictionary) -> bool:
	return has_impact(args) and (int(args.get("taken_built_parcels", 0)) > 0 \
			or int(args.get("displaced_households", 0)) > 0 or int(args.get("taken_project_parcels", 0)) > 0)


## Ret anahtarı: teklif taşıyan `crosses_parcels` için teklif metni, aksi halde aynı anahtar.
static func reject_key(reason_key: StringName, args: Dictionary) -> StringName:
	return CROSSES_PARCELS_OFFER if is_offer(reason_key, args) else reason_key


## Ana satır: "N bina yıkılacak, M hane yerinden edilecek." (bina yoksa boş arsa cümlesi).
static func impact_line(args: Dictionary) -> String:
	var built := int(args.get("taken_built_parcels", 0))
	var households := int(args.get("displaced_households", 0))
	if built == 0 and households == 0:
		return UiText.t(&"expropriation.impact_vacant", {"parcels": int(args.get("taken_parcels", 0))})
	return UiText.t(&"expropriation.impact", {"built": built, "households": households})


## "Bedel: henüz kurulmadı." Sim'de kamulaştırma bedeli yok; yol maliyeti ayrı satırdadır.
static func cost_line() -> String:
	return UiText.t(&"expropriation.cost_line", {"cost": UiText.t(&"public_work.cost.not_built")})


## Ayrıntı satırları (yalnız sim'in sıfırdan büyük saydığı kalemler): alınan arsa, birimler, projeler, bölgeler.
static func detail_lines(args: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(UiText.t(&"expropriation.taken", {"parcels": int(args.get("taken_parcels", 0)),
			"built": int(args.get("taken_built_parcels", 0))}))
	var res := int(args.get("taken_res_units", 0))
	var com := int(args.get("taken_com_units", 0))
	if res > 0 or com > 0:
		out.append(UiText.t(&"expropriation.units", {"res": res, "com": com}))
	var projects := int(args.get("taken_project_parcels", 0))
	if projects > 0:
		out.append(UiText.t(&"expropriation.projects", {"projects": projects}))
	var regions: Dictionary = args.get("taken_regions", {})
	if not regions.is_empty():
		var codes: Array = regions.keys()
		codes.sort()
		var items := PackedStringArray()
		for code: Variant in codes:
			items.append(UiText.t(&"expropriation.region_item", {"region": str(code), "parcels": int(regions[code])}))
		out.append(UiText.t(&"expropriation.regions", {"regions": " · ".join(items)}))
	return out


## Yola yakın ama alınmayan konutlar (yakınlık tepkisi); sim sıfır dediyse boş.
static func nearby_line(args: Dictionary) -> String:
	if int(args.get("nearby_parcels", 0)) <= 0 and int(args.get("nearby_households", 0)) <= 0:
		return ""
	return UiText.t(&"expropriation.nearby", {"parcels": int(args.get("nearby_parcels", 0)),
			"households": int(args.get("nearby_households", 0))})


## Yeniden iskân tahsisi (açık politika) önizleme/olay args'ında var mı?
static func has_resettlement(args: Dictionary) -> bool:
	return bool(args.get("resettlement_applied", false))


## Satırlar `{text, tone}` (tone: ok | danger | muted | normal): ev ayrılan, ev olmayan (yol yine yapılır),
## gösterge bedel.
## Sayılar YALNIZ sim args'ından; tahsis kaydı yoksa boş.
static func resettlement_rows(args: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not has_resettlement(args):
		return rows
	var housed := int(args.get("rehoused_households", 0))
	var unplaced := int(args.get("unplaced_households", 0))
	if housed > 0:
		rows.append({"text": UiText.t(&"resettlement.preview.housed", {"count": housed}), "tone": "ok"})
	else:
		rows.append({"text": UiText.t(&"resettlement.preview.none_housed"), "tone": "danger"})
	if unplaced > 0:
		rows.append({"text": UiText.t(&"resettlement.preview.unplaced", {"count": unplaced}), "tone": "danger"})
	rows.append({"text": UiText.t(&"resettlement.preview.cost",
			{"cost": UiText.money(int(args.get("resettlement_cost", 0)))}), "tone": "normal"})
	if housed > 0:
		rows.append({"text": UiText.t(&"resettlement.preview.relief"), "tone": "muted"})
	return rows


static func resettlement_lines(args: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for row in resettlement_rows(args):
		out.append(String(row["text"]))
	return out


## Politika KAPALIyken ve hane yerinden edilecekken "kapalı, ev ayrılmaz" notu gerekir mi? `policy_enabled`: sim'in
## `PolicyView.enabled` değeri (çağıran, dünyada politika yoksa notu hiç istemez).
static func resettlement_off_needed(args: Dictionary, policy_enabled: bool) -> bool:
	return int(args.get("displaced_households", 0)) > 0 and not has_resettlement(args) and not policy_enabled


## İmleç etiketi: geçerli kamulaştırmalı yolda uzunluk + yıkım sayıları.
static func tip_line(args: Dictionary) -> String:
	return UiText.t(&"road.tip_valid_demolish", {"length": int(args.get("length_m", 0)),
			"built": int(args.get("taken_built_parcels", 0)), "households": int(args.get("displaced_households", 0))})


## Geri alma onayı: geri gelecek bina ve birimler. Önizleme `restored_*` taşıyorsa onlar, yoksa yolun sim kaydı
## (`PublicWorkView`). Geri alınacak yol kamulaştırmalı değilse boş.
static func restore_args(preview: Dictionary, work: PublicWorkView) -> Dictionary:
	if work == null or not work.expropriated:
		return {}
	return {
		"built": int(preview.get("restored_built_parcels", work.taken_built_parcels)),
		"res": int(preview.get("restored_res_units", work.taken_res_units)),
		"com": int(preview.get("restored_com_units", work.taken_com_units)),
	}


static func handles_event(message_key: StringName) -> bool:
	return message_key == EVENT_EXPROPRIATED or message_key == EVENT_RESTORED


## Olay metni: bina yoksa "boş arsa" varyantı (sayılar olay args'ından). Yeniden iskân tahsisi varsa "N hane taşındı;
## K aile için ev yok" eklenir; geri almada `rehoused_returned` varsa dönen hane sayısı eklenir.
static func event_text(event: SimEvent) -> String:
	var built := int(event.args.get("built_parcels", 0))
	var key := event.message_key
	if built == 0 and int(event.args.get("households", 0)) == 0:
		key = StringName("%s_vacant" % event.message_key)
	var text := UiText.t(key, event.args)
	if event.message_key == EVENT_EXPROPRIATED:
		var parts := resettlement_event_parts(event.args)
		if not parts.is_empty():
			text += "; " + "; ".join(parts)
	elif event.message_key == EVENT_RESTORED and int(event.args.get("rehoused_returned", 0)) > 0:
		text += " " + UiText.t(&"resettlement.event.returned", {"count": int(event.args["rehoused_returned"])})
	return text


## "7 hane taşındı", "4 aile için ev yok" (yalnız sıfırdan büyük ve tahsis kaydı varsa).
static func resettlement_event_parts(args: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not has_resettlement(args):
		return out
	if int(args.get("rehoused_households", 0)) > 0:
		out.append(UiText.t(&"resettlement.event.moved", {"count": int(args["rehoused_households"])}))
	if int(args.get("unplaced_households", 0)) > 0:
		out.append(UiText.t(&"resettlement.event.unplaced", {"count": int(args["unplaced_households"])}))
	return out


## Şeritte yol satırına eklenen kısa yıkım özeti (aynı komutun `public_work.expropriated` olayından).
static func strip_suffix(event: SimEvent) -> String:
	var text := UiText.t(&"strip.expropriation_suffix", event.args)
	var parts := resettlement_event_parts(event.args)
	if not parts.is_empty():
		text += " · " + "; ".join(parts)
	return text
