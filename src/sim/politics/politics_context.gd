class_name PoliticsContext
extends RefCounted
## Siyasi motorların ortak, DEĞİŞMEZ girdileri (T-017): doğrulanmış yapılandırmalar ve parsel -> bölge dizini.
## Durum TUTMAZ (kalıcı veri `state.systems["politics"]`); kurulumda bir kez oluşur, tick dışında.

var actors: ActorConfig
var politics: PoliticsConfig
var economy: EconomyConfig
var regions: ParcelRegions


static func create(actor_config: ActorConfig, politics_config: PoliticsConfig, economy_config: EconomyConfig,
		parcels: ParcelSource) -> PoliticsContext:
	var ctx := PoliticsContext.new()
	ctx.actors = actor_config
	ctx.politics = politics_config
	ctx.economy = economy_config
	ctx.regions = ParcelRegions.create(parcels)
	return ctx


## Kurulum sorunu (Türkçe metin) ya da "".
func problem() -> String:
	if actors == null or not actors.is_valid():
		return "aktör yapılandırması geçersiz"
	if politics == null or not politics.is_valid():
		return "siyaset yapılandırması geçersiz: %s" % ("null" if politics == null else politics.error)
	if economy == null or not economy.is_valid():
		return "ekonomi yapılandırması geçersiz"
	if regions == null:
		return "parsel -> bölge dizini yok"
	return ""
