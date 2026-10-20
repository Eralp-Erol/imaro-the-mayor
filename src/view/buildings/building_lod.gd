class_name BuildingLod
extends RefCounted
## Yapı LOD kademeleri ve `visibility_range` aralıkları (T-012; kit spec §7.2, ADR-0001 karar 3). Saf veri: sahne yok.
##
## Kademeler (yakından uzağa): LOD0 (tam modül MultiMesh) -> LOD1 (sade modül MultiMesh) -> HLOD1 (chunk başına
## birleştirilmiş PROXY mesh) -> HLOD2 (süper-chunk başına birleştirilmiş kent kütlesi kutuları).
##
## Godot `visibility_range_*` mesafeyi örneğin AABB MERKEZİNE göre ölçer (T-012'de ölçüldü: 1 km'lik AABB'nin en
## yakın noktası 94 m'de iken merkez 600 m'de olduğundan `visibility_range_end = 500` gizledi). Yani LOD kararı CHUNK
## merkezine göredir; aynı chunk ızgarasındaki kademeler (LOD0/LOD1/HLOD1) aynı merkezi paylaşır, aralarındaki
## çakışma yalnız histerezis içindir. HLOD2 farklı (daha büyük) ızgarada olduğundan HLOD1 ile çakışması geniştir.
##
## Histerezis: komşu kademeler `margin` kadar ÇAKIŞIR (kit_lab/art-director yaklaşımı: aksi halde ilk görünümde marjin
## bandındaki yapı hiçbir kademede görünmez). Geçiş noktası `*_end_m`'dir.

enum Tier { LOD0, LOD1, HLOD1, HLOD2 }

const TIER_COUNT := 4

## LOD0 -> LOD1 geçişi (spec §7.2: LOD0 0-700, LOD1 600-3000).
var lod0_end_m: float = 650.0
var lod0_margin_m: float = 50.0
## LOD1 -> HLOD1 geçişi.
var lod1_end_m: float = 2850.0
var lod1_margin_m: float = 150.0
## HLOD1 -> HLOD2 geçişi: HLOD1 `hlod1_end_m + hlod1_margin_m` sonrasına kadar kalabilir; HLOD2 `hlod2_overlap_m`
## önce (başlangıç marjini 0: ilk karede de görünür) başlar. Farklı ızgara merkezlerinin ayrımını (süper-chunk
## ~2,1 km) örter.
var hlod1_end_m: float = 13000.0
var hlod1_margin_m: float = 500.0
var hlod2_overlap_m: float = 2500.0


## Kademe için aralık: {"begin", "begin_margin", "end", "end_margin"}; 0 = sınır yok.
func range_for(tier: Tier) -> Dictionary:
	match tier:
		Tier.LOD0:
			return {"begin": 0.0, "begin_margin": 0.0, "end": lod0_end_m + lod0_margin_m, "end_margin": lod0_margin_m}
		Tier.LOD1:
			return {"begin": lod0_end_m - lod0_margin_m, "begin_margin": lod0_margin_m,
					"end": lod1_end_m + lod1_margin_m, "end_margin": lod1_margin_m}
		Tier.HLOD1:
			return {"begin": lod1_end_m - lod1_margin_m, "begin_margin": lod1_margin_m,
					"end": hlod1_end_m + hlod1_margin_m, "end_margin": hlod1_margin_m}
		_:
			return {"begin": hlod1_end_m - hlod2_overlap_m, "begin_margin": 0.0, "end": 0.0, "end_margin": 0.0}


func all_ranges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in TIER_COUNT:
		out.append(range_for(t as Tier))
	return out


## Aralıkları bir GeometryInstance3D'ye yazar.
func apply(node: GeometryInstance3D, tier: Tier) -> void:
	var r := range_for(tier)
	node.visibility_range_begin = float(r["begin"])
	node.visibility_range_begin_margin = float(r["begin_margin"])
	node.visibility_range_end = float(r["end"])
	node.visibility_range_end_margin = float(r["end_margin"])


## Tutarlılık: her komşu çift çakışmalı (boşluk yok), sıra artan, marjinler aralığa sığar. Boş = geçerli.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var rs := all_ranges()
	for t in TIER_COUNT:
		var r: Dictionary = rs[t]
		if float(r["begin_margin"]) < 0.0 or float(r["end_margin"]) < 0.0:
			out.append("kademe %d: negatif marjin" % t)
		if float(r["end"]) > 0.0 and float(r["end"]) <= float(r["begin"]):
			out.append("kademe %d: bitiş <= başlangıç" % t)
		if float(r["end"]) > 0.0 and float(r["end_margin"]) >= float(r["end"]) - float(r["begin"]):
			out.append("kademe %d: bitiş marjini aralığı aşıyor" % t)
	for t in TIER_COUNT - 1:
		var a: Dictionary = rs[t]
		var b: Dictionary = rs[t + 1]
		if float(b["begin"]) >= float(a["end"]):
			out.append("kademe %d ile %d çakışmıyor (boşluk)" % [t, t + 1])
		if float(b["begin"]) <= float(a["begin"]):
			out.append("kademe %d başlangıcı sıralı değil" % (t + 1))
	return out


## Komşu iki kademenin çakışma genişliği (m): negatif = boşluk.
func overlap_between(tier_a: Tier, tier_b: Tier) -> float:
	return float(range_for(tier_a)["end"]) - float(range_for(tier_b)["begin"])


## Mesafe `d` için (histerezis dışı, ilk görünüm kuralı) görünür olan kademeler: hidden -> visible ancak
## `begin + begin_margin < d < end - end_margin` içinde (Godot 4 mesafe kuralı; test/denetim için model).
func initially_visible_tiers(d: float) -> Array[int]:
	var out: Array[int] = []
	for t in TIER_COUNT:
		var r := range_for(t as Tier)
		var lo := float(r["begin"]) + float(r["begin_margin"]) if float(r["begin"]) > 0.0 else -INF
		var hi := float(r["end"]) - float(r["end_margin"]) if float(r["end"]) > 0.0 else INF
		if d >= lo and d <= hi:
			out.append(t)
	return out
