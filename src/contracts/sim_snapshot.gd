class_name SimSnapshot
extends SimDto
## Simülasyonun tick sınırındaki ÖZET değer kopyası (ADR-0005). View/UI bunu okur; değiştirmesi sim'i etkilemez.
##
## Kapsam (v1.0): saat, bütçe, meclis, grup tepkileri ve sayaçlar. Parseller ölçekte (on binlerce) snapshot'a
## girmez: `SimFacade.parcel_ids()/parcel_views()` ile sınırlı sorgulanır;
## render'ın toplu sütun verisi v1.1 uzantısıdır.
## Snapshot hash'i (`StateHash.of(to_dict())`) sim durum hash'i DEĞİLDİR (hız gibi görünüm alanları içerir).
## `extensions`: MINOR sürüm beklemeden deneysel alanlar için ad alanlı (`x.<hat>.<ad>`) ilkel değerler.

var contract_version: String = SimContract.VERSION
var provenance: StringName = SimContract.PROVENANCE_SIM
## Dünyanın kimliği (WorldData.world_id) ve senaryo/kampanya kimliği (mock: senaryo kimliği).
var world_id: StringName = &""
var scenario_id: StringName = &""
var clock: ClockView = ClockView.new()
## Bu snapshot alındığında yayımlanmış en büyük olay sırası (events_since imleci için).
var last_event_seq: int = 0
var parcel_count: int = 0
var budget: BudgetView = BudgetView.new()
var council: CouncilView = CouncilView.new()
## Grup başına tepki, grup referans dizgesine (`actor.<tür>.<id>`) göre sıralı (SIM-09: toplam skor yok).
var group_reactions: Array[GroupReactionView] = []
var extensions: Dictionary = {}


func tick() -> int:
	return clock.tick


func is_mock() -> bool:
	return provenance != SimContract.PROVENANCE_SIM


func to_dict() -> Dictionary:
	return {
		"contract_version": contract_version, "provenance": provenance, "world_id": world_id,
		"scenario_id": scenario_id, "clock": clock.to_dict(), "last_event_seq": last_event_seq,
		"parcel_count": parcel_count, "budget": budget.to_dict(), "council": council.to_dict(),
		"group_reactions": SimDto.dicts_of(group_reactions), "extensions": SimContract.canonical(extensions),
	}


## Uyumsuz MAJOR sürümde null döner (çağıran `SimContract.is_compatible` ile nedenini raporlar).
static func from_dict(d: Dictionary) -> SimSnapshot:
	var version := str(d.get("contract_version", ""))
	if not SimContract.is_compatible(version):
		return null
	var s := SimSnapshot.new()
	s.contract_version = version
	s.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	s.world_id = SimContract.to_name(d.get("world_id", ""))
	s.scenario_id = SimContract.to_name(d.get("scenario_id", ""))
	s.clock = ClockView.from_dict(d.get("clock", {}) if d.get("clock") is Dictionary else {})
	s.last_event_seq = SimContract.to_int(d.get("last_event_seq"))
	s.parcel_count = SimContract.to_int(d.get("parcel_count"))
	s.budget = BudgetView.from_dict(d.get("budget", {}) if d.get("budget") is Dictionary else {})
	s.council = CouncilView.from_dict(d.get("council", {}) if d.get("council") is Dictionary else {})
	for gd: Variant in d.get("group_reactions", []):
		if gd is Dictionary:
			s.group_reactions.append(GroupReactionView.from_dict(gd))
	s.extensions = (d.get("extensions", {}) as Dictionary).duplicate(true) if d.get("extensions") is Dictionary else {}
	return s
