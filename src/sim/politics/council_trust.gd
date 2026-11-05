class_name CouncilTrust
extends RefCounted
## D-021 (SAHİP, "Meclis güveni düşsün"): bir yol yıkımı insanları yerinden ederse, o halkı temsil eden meclis
## üyelerinin oyuncuya güveni düşer ve imar planları reddedilmeye yaklaşır. Büyüklük, eşik ve hangi üyelerin etkilendiği
## SAHİBİN SÖZÜ DEĞİL: `data/politics/reactions.json` `council_trust` (ÇALIŞMA MODELİ, F05-C); kodda sayı yok.
##
## Kural (haftalık, `PoliticsSystem` tarama sonunda; halk tepkisinden meclise ölçülen yol B-030):
##  1. Etkin yerinden edilen hane = tepki defterindeki (`displaced`) satırların `window_days` boyunca DOĞRUSAL sönen
##     toplamı; evi bulunan aile yalnız kalan tepkisi kadar sayılır (`ReactionRehousing.still_unhoused`, yeniden iskân
##     politikasıyla tek karar noktası). Geri alınan yolun satırları silindiği için sayılmaz.
##  2. Hedef kesinti (pm) = (etkin hane - eşik) x hane başına pm, [0, tavan]. Eşik altında hiçbir şey yazılmaz.
##  3. Etkilenen üyeler = temsil ettiği kesimlerden biri `cohorts` listesindeki kohortun kesimi olan üyeler (veri).
##  4. Kesinti hedefe hemen iner; hedef düştüğünde (sönme, yeniden iskân) tarama başına en çok `recover_per_scan_pm`
##     toparlanır. Durum `politics.council_trust = {penalty {üye: pm}, changes}`; YALNIZ ilk etkide yaratılır
##     (yıkımsız koşuda durum ve hash değişmez, GOLDEN A/B).
##  5. Her değişiklik üye adına bir NEDEN kaydı yazar (SIM-12): yerinden edilen hane, hedef, uygulanan kesinti; öznesi
##     yolun komut(lar)ı. Kesinti oy girdisine (`CouncilEngine.member_factors`) ve üye görünümüne `trust` olarak biner;
##     ilişki kaydını (ActorStore) DEĞİŞTİRMEZ: toparlanma ve tavan burada tek yerde.
## Belediye bina yaratmaz (CAN-03): yalnız güven koşulu değişir. Saf, tamsayı, rastgelelik yok.

const KEY := "council_trust"
const SCALE := 1000
## Kayıt eşiği: skor = uygulanan kesinti (pm) >= 1 <=> "güven kesintisi yürürlükte" (positive); 0'a dönünce negative.
const REASON_THRESHOLD := 1
const FACTOR_UNHOUSED := &"reason.factor.unhoused_households"
const FACTOR_TARGET := &"reason.factor.council_trust_target"
const FACTOR_APPLIED := &"reason.factor.council_trust_drop"
const CODE_DROP := &"displacement_trust"
const CODE_RECOVER := &"displacement_trust_recovery"


## Haftalık tarama. Yapılandırma kapalıysa/tepki defteri yoksa YENİ kesinti yazılmaz; kesinti tablosu zaten varsa (veri
## sonradan kapatıldı ya da `cohorts` değişti: `reactions.json` digest dışı, eski kayıt yeni veriyle yüklenebilir)
## kapsam dışı kalan her üyenin hedefi 0'dır ve normal toparlanma çalışır (kesinti donup oya binmeye devam etmez).
## Durum yokken ve kural kapalıyken hiçbir şey yazılmaz (hash değişmez).
static func scan(state: GameState, ctx: PoliticsContext) -> void:
	var cfg: Dictionary = ctx.politics.reactions["council_trust"]
	var pol := PoliticsState.data(state)
	var live: bool = bool(cfg["enabled"]) and PublicWorksState.has_reactions(state)
	if not live and not pol.has(KEY):
		return
	var reading := {"households": 0, "commands": []}
	var target := 0
	var members: Array[String] = []
	if live:
		reading = reading_of(state, cfg)
		target = target_of(cfg, int(reading["households"]))
		members = affected_members(state, ctx, cfg)
	if not pol.has(KEY):
		if target <= 0 or members.is_empty():
			return
		pol[KEY] = {"penalty": {}, "changes": 0}
	var table: Dictionary = pol[KEY]["penalty"]
	var keys: Array = members.duplicate()
	for member: String in table:
		if not keys.has(member):
			keys.append(member)
	keys.sort()
	for member: String in keys:
		var before := int(table.get(member, 0))
		var goal := target if members.has(member) else 0
		var after := goal if goal > before else maxi(goal, before - int(cfg["recover_per_scan_pm"]))
		if after == before:
			continue
		table[member] = after
		pol[KEY]["changes"] = int(pol[KEY]["changes"]) + 1
		_record(state, ctx, cfg, member, reading, goal, after, after < before)


## Üyenin güvenine binen kesinti (pm, >= 0); durum yoksa 0.
static func penalty(state: GameState, member_key: String) -> int:
	var d: Variant = PoliticsState.data(state).get(KEY, null)
	return int(d["penalty"].get(member_key, 0)) if d is Dictionary else 0


## Üyenin oyuncuya güveni (ilişki güveni - kesinti, -1000..1000). Oy girdisi ve üye görünümü TEK bu işlevi okur.
static func effective_trust(state: GameState, relation_trust: int, member_key: String) -> int:
	return clampi(relation_trust - penalty(state, member_key), -SCALE, SCALE)


## Hedef kesinti (pm): eşiği aşan etkin hane x hane başına pm, [0, tavan]. Saf.
static func target_of(cfg: Dictionary, households: int) -> int:
	return clampi((households - int(cfg["threshold_households"])) * int(cfg["drop_per_household_pm"]), 0,
		int(cfg["cap_pm"]))


## Etkin yerinden edilen hane okuması: {households (tam sayı, aşağı yuvarlı), commands (katkısı olan komutlar, artan)}.
## `reaction_rows` satırları [tick, hane, komut]; yeniden iskân rahatlaması `ReactionAgenda.local_readings` ile aynı
## ölçekle (komut x bölge toplamı) tek noktadan.
@warning_ignore("integer_division")
static func reading_of(state: GameState, cfg: Dictionary) -> Dictionary:
	var window := maxi(int(cfg["window_days"]), 1)
	var rehoused := ReactionRehousing.index(state)
	var book: Dictionary = PublicWorksState.data(state).get("displaced", {})
	var codes: Array = book.keys()
	codes.sort()
	var total_milli := 0
	var commands: Array = []
	for code: String in codes:
		var by_command := {}
		for row: Array in PublicWorksState.reaction_rows(state, "displaced", code):
			var age := state.tick - int(row[0])
			if age < 0 or age >= window:
				continue
			var entry: Dictionary = by_command.get(int(row[2]), {"milli": 0, "households": 0})
			entry["milli"] = int(entry["milli"]) + int(row[1]) * SCALE * (window - age) / window
			entry["households"] = int(entry["households"]) + int(row[1])
			by_command[int(row[2])] = entry
		var ids: Array = by_command.keys()
		ids.sort()
		for command_id: int in ids:
			var entry: Dictionary = by_command[command_id]
			var total := int(entry["households"])
			var kept := ReactionRehousing.still_unhoused(code, command_id, total, rehoused)
			var milli := int(entry["milli"]) * kept / maxi(total, 1)
			if milli > 0:
				total_milli += milli
				if not commands.has(command_id):
					commands.append(command_id)
	commands.sort()
	return {"households": total_milli / SCALE, "commands": commands}


## Etkilenen üyeler (sıralı anahtar): temsil ettiği kesimlerden biri `cohorts` kohortlarından birinin kesimi.
static func affected_members(state: GameState, ctx: PoliticsContext, cfg: Dictionary) -> Array[String]:
	var wanted := {}
	var blocs: Dictionary = PoliticsState.data(state)["blocs"]
	for bloc_key: String in blocs:
		if (cfg["cohorts"] as Array).has(String(blocs[bloc_key]["cohort"])):
			wanted[bloc_key] = true
	var out: Array[String] = []
	var members: Array = ctx.politics.council["members"]
	for member: String in members:
		for bloc_key: String in ActorStore.actor_ref(state, member)["state"].get("constituency_blocs", []):
			if wanted.has(bloc_key):
				out.append(member)
				break
	out.sort()
	return out


static func _record(state: GameState, ctx: PoliticsContext, cfg: Dictionary, member: String, reading: Dictionary,
		target: int, applied: int, recovering: bool) -> void:
	var cap := int(ctx.politics.cadence["cause_cap"])
	var commands: Array = reading["commands"]
	var newest: Array = commands.slice(maxi(commands.size() - cap, 0))
	var subjects := PackedStringArray()
	for command_id: int in newest:
		subjects.append(String(SimContract.ref(SimContract.REF_COMMAND, command_id)))
	var source := "" if subjects.is_empty() else subjects[subjects.size() - 1]
	var factors: Array = [
		{"name": FACTOR_UNHOUSED, "value": int(reading["households"]), "weight": 0, "source_ref": source},
		{"name": FACTOR_TARGET, "value": target, "weight": 0, "source_ref": source},
		{"name": FACTOR_APPLIED, "value": applied, "weight": SCALE, "source_ref": source},
	]
	var id := state.record_reason(StringName(member), StringName(cfg["decision"]), factors, REASON_THRESHOLD,
		CODE_RECOVER if recovering else CODE_DROP, subjects)
	if id > 0:
		PoliticsState.count(state, "reason_records")
