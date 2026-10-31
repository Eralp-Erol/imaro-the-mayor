class_name CouncilWhy
extends RefCounted
## Meclis oylamasının NEDENİ (SIM-12): oylama çözülürken üyelerin KAYITLI `council.vote` gerekçelerinden (ReasonLog)
## etken başına toplam etkiyi çıkarır. Yeni etken uydurmaz ve yeni sayı/eşik taşımaz; yalnız kayıtlı değer x ağırlık
## katkılarını (`SimContract.contribution`) toplar. Sonuç oylama kaydına `vote["why"]` olarak yazılır (kaydedilir,
## kaydedilmiş gerekçeden yeniden türetilmez: gerekçe kayıtları budanabilir):
##   {members, factors [{name, net, for, against}], infra_load_pm?, infra_region?}
## - `net`  = Σ üye katkısı (eksi = hayıra çeker); Σ net = Σ üye gerekçe skoru (kayıtla aynı birim).
## - `for` / `against` = katkısı artı / eksi olan üye sayısı. Katkısı hiç sıfırdan farklı olmayan etken yazılmaz.
## - Sıra: |net| azalan, eşitlikte ad artan (deterministik).
## - `infra_*`: imar oylamasında uygulanabilirliği belirleyen en yüksek altyapı yükü (binde) ve bölgesi.
## `CouncilEngine._resolve` yalnız `unplanned_land_enabled` iken çağırır (bayrak kapalıyken hiçbir şey yazılmaz).


## `reason_ids`: oylamada üyelerin gerekçe kimlikleri (az önce yazıldı). `infra`: CouncilEngine.peak_infra çıktısı.
static func build(state: GameState, reason_ids: Array, infra: Dictionary) -> Dictionary:
	var net := {}
	var yes_side := {}
	var no_side := {}
	var members := 0
	for reason_id: int in reason_ids:
		var rec := state.reasons.peek(reason_id)
		if rec.is_empty():
			continue
		members += 1
		for factor: Dictionary in rec["factors"]:
			var key := String(factor["name"])
			var share := SimContract.contribution(int(factor["value"]), int(factor["weight"]))
			net[key] = int(net.get(key, 0)) + share
			if share > 0:
				yes_side[key] = int(yes_side.get(key, 0)) + 1
			elif share < 0:
				no_side[key] = int(no_side.get(key, 0)) + 1
	var factors: Array = []
	var names: Array = net.keys()
	names.sort()
	for key: String in names:
		if int(net[key]) == 0 and int(yes_side.get(key, 0)) + int(no_side.get(key, 0)) == 0:
			continue
		factors.append({"name": key, "net": int(net[key]), "for": int(yes_side.get(key, 0)),
			"against": int(no_side.get(key, 0))})
	factors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma := absi(int(a["net"]))
		var mb := absi(int(b["net"]))
		return ma > mb or (ma == mb and String(a["name"]) < String(b["name"])))
	var why := {"members": members, "factors": factors}
	if int(infra.get("peak_pm", -1)) >= 0:
		why["infra_load_pm"] = int(infra["peak_pm"])
		why["infra_region"] = String(infra["region"])
	return why
