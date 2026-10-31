class_name ExpropriationText
extends RefCounted
## Kamulaştırma (T-042b, D-011, ADR-0005 Ek F) metin yardımcısı: SAF, düğüm yok. Sayılar YALNIZ sim'in
## `CommandResult.args` ve olay args'ından gelir (`taken_*`, `displaced_households`, `nearby_*`, `restored_*`);
## burada hesap ya da tahmin yoktur. Bedel: sim'de kurulu değil (Q-017/T-014, Q-003): "Bedel: henüz
## kurulmadı", para simgesi/sayısı yok.
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


## Olay metni: bina yoksa "boş arsa" varyantı (sayılar olay args'ından).
static func event_text(event: SimEvent) -> String:
	var built := int(event.args.get("built_parcels", 0))
	var key := event.message_key
	if built == 0 and int(event.args.get("households", 0)) == 0:
		key = StringName("%s_vacant" % event.message_key)
	return UiText.t(key, event.args)


## Şeritte yol satırına eklenen kısa yıkım özeti (aynı komutun `public_work.expropriated` olayından).
static func strip_suffix(event: SimEvent) -> String:
	return UiText.t(&"strip.expropriation_suffix", event.args)
