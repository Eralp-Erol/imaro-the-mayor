class_name CouncilWhyFactor
extends SimDto
## Meclis oylamasının nedeni (SIM-12), etken başına: üyelerin kayıtlı `council.vote` etkeninin oylamaya TOPLAM etkisi.
## `net` = Σ üye katkısı (`ReasonFactor.contribution`, kayıtla aynı sabit nokta birimi; eksi = hayıra çeker,
## artı = evete), yani oylamadaki üye skorlarının toplamı etkenlere bölünmüş halidir. Yeni etken yoktur: yalnız
## gerekçe kaydına giren etkenler (`reason.factor.*`). `for_members` / `against_members` = o etkenin katkısı
## artı / eksi olan üye sayısı.
## İSTEĞE BAĞLI alan (sözleşme sürümü değişmez): `CouncilVoteView.why_factors` boşsa sim neden kaydı yazmamıştır.

var name_key: StringName = &""
var net: int = 0
var for_members: int = 0
var against_members: int = 0


static func make(key: StringName, net_effect: int, for_count: int, against_count: int) -> CouncilWhyFactor:
	var f := CouncilWhyFactor.new()
	f.name_key = key
	f.net = net_effect
	f.for_members = for_count
	f.against_members = against_count
	return f


func to_dict() -> Dictionary:
	return {"name_key": name_key, "net": net, "for_members": for_members, "against_members": against_members}


static func from_dict(d: Dictionary) -> CouncilWhyFactor:
	return make(SimContract.to_name(d.get("name_key", "")), SimContract.to_int(d.get("net")),
		SimContract.to_int(d.get("for_members")), SimContract.to_int(d.get("against_members")))
