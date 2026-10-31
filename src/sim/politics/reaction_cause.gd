class_name ReactionCause
extends RefCounted
## T-042b · Kamulaştırma/yakınlık tepkisinin NEDEN kaydı (D-011, SIM-12). Kesimin tepki kararı (`bloc.react`) hesabına
## `displacement`/`proximity` sinyalleri tablo faktörü olarak girmez (karar tablosu = hash'e giren yapılandırma); bunun
## yerine kesim tepkisini değerlendirirken AYRI bir gerekçe kaydı yazılır: etkenler `displaced_households` ve
## `road_proximity` (kesimin gördüğü sinyal, pm), gösterim etkeni `displaced_household_count` (penceredeki gerçek hane
## sayısı); `subjects` = tepkiye yol açan komut(lar) ve alınan parseller. Tepki kararı bu kaydı ebeveyn olarak alır,
## kesim tepkisi (`GroupReactionView.reason_ids`) ve gündem öğesi ona bağlanır: UI nedensellik uydurmaz.
##
## YALNIZ tepki defteri (`PublicWorksState.has_reactions`) varken çağrılır; kamulaştırmasız koşuda hiçbir şey yazılmaz.
## Salt okur; tek yazdığı şey gerekçe kaydıdır. Sayılar `PoliticsConfig.reactions["cause"]` (veri) içindedir.

const FACTOR_DISPLACED := &"reason.factor.displaced_households"
const FACTOR_PROXIMITY := &"reason.factor.road_proximity"
const FACTOR_COUNT := &"reason.factor.displaced_household_count"
const CODE := &"road_expropriation"


## Kesim için neden kaydı yazar. `by_region`: bölge sinyalleri (BlocEngine). Dönüş: {} (uygulanmaz / yazılamadı) ya da
## {id, command_refs, parcel_refs, households}.
static func record(state: GameState, ctx: PoliticsContext, key: String, bloc: Dictionary,
		by_region: Dictionary) -> Dictionary:
	var signals: Dictionary = bloc["signals"]
	var displacement := int(signals.get("displacement", 0))
	var proximity := int(signals.get("proximity", 0))
	if not PublicWorksState.has_reactions(state) or (displacement <= 0 and proximity <= 0):
		return {}
	var regions := _regions(ctx, bloc, by_region)
	var found := _ledger(state, ctx, regions)
	var commands: Array = found["commands"]
	if commands.is_empty():
		return {}
	var cap := int(ctx.politics.cadence["cause_cap"])
	var newest := commands.slice(maxi(commands.size() - cap, 0))
	var refs := PackedStringArray()
	for command_id: int in newest:
		refs.append(String(SimContract.ref(SimContract.REF_COMMAND, command_id)))
	var parcels := _taken_parcels(state, ctx, newest, regions, cap)
	var subjects := refs.duplicate()
	subjects.append_array(parcels)
	var cfg: Dictionary = ctx.politics.reactions["cause"]
	var source := refs[refs.size() - 1]
	var factors: Array = [
		{"name": FACTOR_DISPLACED, "value": displacement, "weight": int(cfg["weights"]["displaced_households"]),
			"source_ref": source},
		{"name": FACTOR_PROXIMITY, "value": proximity, "weight": int(cfg["weights"]["road_proximity"]),
			"is_estimate": true, "source_ref": source},  # mesafeye bağlı ağırlık: tahmin
		{"name": FACTOR_COUNT, "value": int(found["households"]), "weight": 0, "source_ref": source},
	]
	var id := state.record_reason(StringName(key), StringName(cfg["decision"]), factors, int(cfg["threshold"]), CODE,
		subjects)
	if id < 1:
		return {}
	return {"id": id, "command_refs": refs, "parcel_refs": parcels, "households": int(found["households"])}


## Mahalle ölçekli neden kaydı (`ReactionAgenda.local_readings` okuması): TEK komutun (yolun) o bölgedeki yerinden
## edilmesi. Etken değerleri mahalle ölçekli pm (yerinden edilen / yakındaki haneler, mahalle büyüklüğüne oranlı),
## gösterim etkeni gerçek hane sayısı; özneler = komut + o komutun hâlâ alınmış parselleri (bölgede). Kesim sinyali
## aranmaz (bölge ölçekli sinyal küçük olabilir). Dönüş `record` ile aynı biçim; yazılamazsa {}.
static func record_local(state: GameState, ctx: PoliticsContext, key: String, reading: Dictionary) -> Dictionary:
	if not PublicWorksState.has_reactions(state) or int(reading.get("households", 0)) <= 0:
		return {}
	var command_id := int(reading["command_id"])
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, command_id))
	var regions: Array[String] = [String(reading["code"])]
	var parcels := _taken_parcels(state, ctx, [command_id], regions, int(ctx.politics.cadence["cause_cap"]))
	var subjects := PackedStringArray([ref])
	subjects.append_array(parcels)
	var cfg: Dictionary = ctx.politics.reactions["cause"]
	var factors: Array = [
		{"name": FACTOR_DISPLACED, "value": int(reading["displacement_pm"]),
			"weight": int(cfg["weights"]["displaced_households"]), "source_ref": ref},
		{"name": FACTOR_PROXIMITY, "value": int(reading["proximity_pm"]),
			"weight": int(cfg["weights"]["road_proximity"]), "is_estimate": true, "source_ref": ref},
		{"name": FACTOR_COUNT, "value": int(reading["households"]), "weight": 0, "source_ref": ref},
	]
	var id := state.record_reason(StringName(key), StringName(cfg["decision"]), factors, int(cfg["threshold"]), CODE,
		subjects)
	if id < 1:
		return {}
	return {"id": id, "command_refs": PackedStringArray([ref]), "parcel_refs": parcels,
		"households": int(reading["households"])}


## Kesimin tepkisini besleyen bölgeler (sıralı kod): kesim payı olan ve bölge sinyali sıfırdan büyük olanlar
## (tepe kipinde yalnız `min_share` ve üstü: kesim sinyali de yalnız onlardan türer).
static func _regions(ctx: PoliticsContext, bloc: Dictionary, by_region: Dictionary) -> Array[String]:
	var peak: bool = ctx.politics.blocs["blend_mode"] == "peak"
	var min_share := int(ctx.politics.blocs["min_share"])
	var shares: Dictionary = bloc["exposure"]
	var codes: Array = shares.keys()
	codes.sort()
	var out: Array[String] = []
	for code: String in codes:
		var row: Dictionary = by_region.get(code, {})
		if peak and int(shares[code]) < min_share:
			continue
		if int(row.get("displacement", 0)) > 0 or int(row.get("proximity", 0)) > 0:
			out.append(code)
	return out


## Penceredeki (sönmemiş) defter satırlarından komut kimlikleri (artan, tekrarsız) ve yerinden edilen hane toplamı.
static func _ledger(state: GameState, ctx: PoliticsContext, regions: Array[String]) -> Dictionary:
	var window := int(ctx.politics.blocs["reaction_window"])
	var commands: Array = []
	var households := 0
	for book in PublicWorksState.REACTION_BOOKS:
		for code in regions:
			for row: Array in PublicWorksState.reaction_rows(state, book, code):
				var age := state.tick - int(row[0])
				if age < 0 or age >= window:
					continue
				if book == "displaced":
					households += int(row[1])
				if not commands.has(int(row[2])):
					commands.append(int(row[2]))
	commands.sort()
	return {"commands": commands, "households": households}


## Bu komutların hâlâ alınmış parselleri (bölgede), artan kimlikle, en çok `cap` tane. Geri alınmış yolun parseli geri
## verildiği için listede yoktur (tepki yine de komuta bağlıdır).
static func _taken_parcels(state: GameState, ctx: PoliticsContext, commands: Array, regions: Array[String],
		cap: int) -> PackedStringArray:
	var taken: Dictionary = PublicWorksState.data(state).get("taken", {})
	var ids: Array = taken.keys()
	ids.sort()
	var out := PackedStringArray()
	for id: int in ids:
		if out.size() >= cap:
			break
		if commands.has(int(taken[id])) and regions.has(ctx.regions.code_of(id)):
			out.append(String(SimContract.parcel_ref(id)))
	return out
