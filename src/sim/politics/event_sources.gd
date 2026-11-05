class_name EventSources
extends RefCounted
## Olay şablonlarının okuduğu durum kaynakları (T-017, political-events §2 `Condition` kaynakları): hepsi mevcut sim
## durumundan türeyen 0..1000 (ya da sayaç) tamsayılar; yeni "sihirli" gösterge yok. SAF okuma: durumu DEĞİŞTİRMEZ
## (yatırımcı olumsuz karar sayacı hariç; o `track` ile ayrıca ilerletilir). Adlar `EventSpec.SOURCES`.

const SCALE := 1000


## Tüm kaynaklar: {ad: int}. `rows`: EconomyQuery.region_stats.
static func compute(state: GameState, ctx: PoliticsContext, rows: Array[Dictionary]) -> Dictionary:
	var pol := PoliticsState.data(state)
	var trigger := trigger_bloc(state, ctx)
	var bloc: Dictionary = pol["blocs"].get(trigger, {})
	var out := {
		"bloc.react_tier": tier_index(ctx, str(bloc.get("eval", {}).get("tier", ""))) if not bloc.is_empty() else 0,
		"bloc.G": int(bloc.get("G", 0)), "bloc.amp": int(bloc.get("amp", 0)), "bloc.organizer": int(bloc.get("org", 0)),
		"investor.declines_recent": declines_recent(state, ctx),
		"politics.council_instability": council_instability(state),
		"politics.reversals_180d": reversals(state, ctx),
		"politics.unrest": unrest(state), "politics.permit_delay_days": permit_delay(state),
	}
	out.merge(_council_sources(state, ctx))
	out.merge(_media_sources(state, ctx))
	out.merge(_service_sources(pol, rows))
	return out


## Tetik kesimi: en yüksek basamaklı tepki, eşitlikte en yüksek şikâyet, sonra anahtar sırası; yoksa "".
static func trigger_bloc(state: GameState, ctx: PoliticsContext) -> String:
	var best := ""
	var best_rank := -1
	var best_g := -1
	for key in PoliticsState.bloc_keys(state):
		var bloc: Dictionary = PoliticsState.data(state)["blocs"][key]
		var rank := tier_index(ctx, str(bloc["eval"]["tier"]))
		if rank > best_rank or (rank == best_rank and int(bloc["G"]) > best_g):
			best = key
			best_rank = rank
			best_g = int(bloc["G"])
	return best


## Basamak adı -> 1..n (boş = 0). Sıra `bloc.react` tablosundaki basamak sırasıdır.
static func tier_index(ctx: PoliticsContext, tier: String) -> int:
	var tiers: Array = ctx.actors.table(ctx.politics.blocs["react_decision"])["tiers"]
	for i in tiers.size():
		if tiers[i]["id"] == tier:
			return i + 1
	return 0


## Şablondaki eşik değeri: basamak adı ya da tamsayı.
static func threshold_value(ctx: PoliticsContext, raw: Variant) -> int:
	return tier_index(ctx, raw) if typeof(raw) == TYPE_STRING else int(raw)


# --- Yatırımcı ---

## Penceredeki gerekçeli olumsuz yatırımcı kararı sayısı (kümülatif sayaçtan; `track` ilerletir).
static func declines_recent(state: GameState, ctx: PoliticsContext) -> int:
	var horizon := int(ctx.politics.events["declines_days"])
	var total := 0
	for entry: Array in PoliticsState.data(state)["declines"]["ticks"]:
		if int(entry[0]) >= state.tick - horizon:
			total += int(entry[1])
	return total


## Ekonomi sayacından yeni olumsuz kararları kaydeder, eskiyi budar (haftalık).
static func track(state: GameState, ctx: PoliticsContext) -> void:
	var declines: Dictionary = PoliticsState.data(state)["declines"]
	var total := int(EconomyQuery.totals(state).get("declines_recorded", 0))
	if total > int(declines["last_total"]):
		(declines["ticks"] as Array).append([state.tick, total - int(declines["last_total"])])
	declines["last_total"] = total
	var horizon := int(ctx.politics.events["declines_days"])
	var kept: Array = []
	for entry: Array in declines["ticks"]:
		if int(entry[0]) >= state.tick - horizon:
			kept.append(entry)
	declines["ticks"] = kept


# --- Meclis / huzursuzluk ---

static func _resolved(state: GameState) -> Array:
	var out: Array = []
	for vote: Dictionary in PoliticsState.data(state)["council"]["votes"]:
		if vote["status"] != CouncilEngine.PENDING:
			out.append(vote)
	return out


## Son 5 kapanmış oylamanın ortalama bölünmüşlüğü: 1000 - |evet-hayır| x 1000 / koltuk.
@warning_ignore("integer_division")
static func council_instability(state: GameState) -> int:
	var resolved := _resolved(state)
	var recent := resolved.slice(maxi(resolved.size() - 5, 0))
	if recent.is_empty():
		return 0
	var total := 0
	for vote: Dictionary in recent:
		var seats := maxi((vote["positions"] as Array).size(), 1)
		total += SCALE - absi(int(vote["yes"]) - int(vote["no"])) * SCALE / seats
	return total / recent.size()


## Penceredeki ardışık oylama sonucu tersine dönüşleri (aynı türde kabul -> ret ya da ret -> kabul).
static func reversals(state: GameState, ctx: PoliticsContext) -> int:
	var horizon := int(ctx.politics.events["reversals_days"])
	var count := 0
	var last_by_kind := {}
	for vote: Dictionary in _resolved(state):
		if int(vote["resolved_tick"]) < state.tick - horizon:
			continue
		var previous: Variant = last_by_kind.get(vote["kind"], null)
		if previous != null and previous != vote["status"]:
			count += 1
		last_by_kind[vote["kind"]] = vote["status"]
	return count


## Muhalefet/protesto yoğunluğu: tepkisi destek/nötr olmayan kesimlerin en yüksek yoğunluğu.
static func unrest(state: GameState) -> int:
	var peak := 0
	for key in PoliticsState.bloc_keys(state):
		var eval_data: Dictionary = PoliticsState.data(state)["blocs"][key]["eval"]
		if eval_data["reaction"] == "oppose" or eval_data["reaction"] == "protest":
			peak = maxi(peak, int(eval_data["intensity"]))
	return peak


## Bekleyen oylamaların en uzun bekleme günü (izin gecikmesi).
static func permit_delay(state: GameState) -> int:
	var longest := 0
	for vote: Dictionary in PoliticsState.data(state)["council"]["votes"]:
		if vote["status"] == CouncilEngine.PENDING:
			longest = maxi(longest, state.tick - int(vote["opened_tick"]))
	return longest


@warning_ignore("integer_division")
static func _council_sources(state: GameState, ctx: PoliticsContext) -> Dictionary:
	var failed := 0
	var dissent := 0
	var horizon := int(ctx.politics.events["reversals_days"])
	for vote: Dictionary in _resolved(state):
		if vote["kind"] == "budget" and int(vote["resolved_tick"]) >= state.tick - horizon:
			failed = 1 if vote["status"] == CouncilEngine.FAILED else 0
			dissent = int(vote["no"]) * SCALE / maxi((vote["positions"] as Array).size(), 1)
	var player := ActorStore.protagonist_key(state, ctx.actors)
	var members: Array = ctx.politics.council["members"]
	var trust_total := 0
	for member: String in members:
		trust_total += CouncilTrust.effective_trust(state,
			int(ActorStore.relation(state, ctx.actors, member, player)["trust"]), member)
	var trust_avg := 0 if members.is_empty() else trust_total / members.size()
	return {"council.budget_vote_failed": failed, "council.dissent": dissent,
		"council.trust_gap": clampi((SCALE - trust_avg) / 2, 0, SCALE)}


static func _media_sources(state: GameState, ctx: PoliticsContext) -> Dictionary:
	var media: Dictionary = PoliticsState.data(state)["media"]
	var recent: bool = int(media["last_tick"]) >= 0 \
		and int(media["last_tick"]) >= state.tick - int(ctx.politics.events["media_days"])
	var last: Dictionary = media["last"] if recent else {}
	return {"media.published_recent": 1 if recent else 0, "media.newsworthiness": int(last.get("newsworthiness", 0)),
		"media.lean_abs": absi(int(last.get("lean", 0))), "media.fact_abs": absi(int(last.get("fact", 0)))}


static func _service_sources(pol: Dictionary, rows: Array[Dictionary]) -> Dictionary:
	var overload := 0
	var growth := 0
	var stress := 0
	for code: String in pol["service"]["overload_days"]:
		overload = maxi(overload, int(pol["service"]["overload_days"][code]))
	for code: String in pol["service"]["growth"]:
		growth = maxi(growth, int(pol["service"]["growth"][code]))
	for row in rows:
		stress = maxi(stress, int(row["infra_load_pm"]))
	return {"service.overload_days": overload, "service.growth_pm": growth, "service.stress_pm": stress}


# --- Siyasi risk sinyali (investor.political_risk_signal) ---

## Yatırımcı siyasi risk sinyali (0..1000): meclis istikrarsızlığı, karar tersine dönüşleri, huzursuzluk, izin
## gecikmesi.
## Bölgeye olay etkisi (`risk.adjust`) eklenir. T-013 yatırım kararına faktör olarak girebilir (entegrasyon isteği).
@warning_ignore("integer_division")
static func risk_base(state: GameState, ctx: PoliticsContext) -> int:
	var cfg: Dictionary = ctx.politics.events
	var components := [
		[int(cfg["risk_instability"]), council_instability(state)],
		[int(cfg["risk_reversals"]), mini(reversals(state, ctx) * SCALE / int(cfg["reversals_full"]), SCALE)],
		[int(cfg["risk_unrest"]), unrest(state)],
		[int(cfg["risk_permit"]), mini(permit_delay(state) * SCALE / int(cfg["permit_full_days"]), SCALE)],
	]
	var total := 0
	var weights := 0
	for pair: Array in components:
		total += int(pair[0]) * int(pair[1])
		weights += int(pair[0])
	return 0 if weights == 0 else total / weights


## Haftalık: bölge başına sinyal düzeyi yazılır (taban + olay etkisi).
static func update_risk(state: GameState, ctx: PoliticsContext, rows: Array[Dictionary]) -> void:
	var risk: Dictionary = PoliticsState.data(state)["risk"]
	var base := risk_base(state, ctx)
	for row in rows:
		var code := String(row["code"])
		risk["level"][code] = clampi(base + int(risk["adjust"].get(code, 0)), 0, SCALE)
