class_name PoliticsBootstrap
extends RefCounted
## Ekonomi + aktör + siyaset katmanlarını tek `SimFacadeImpl`e kurar (T-017). Kayıt sırası SABİTTİR:
## ekonomi, aktörler (kendi sistemlerinden önce), siyaset. Varsayılan `SimFacadeImpl.create` siyaseti KURMAZ (mevcut
## davranış korunur); uygulama/entegrasyon bunu çağırır. `requires_council` (Q-014) yapılandırmadan gelir.


## Siyasi katmanlı facade. Geçersiz kurulumda push_error + null.
static func create(world_seed: int, parcels: ParcelSource, economy_config: EconomyConfig = null,
		stock: ExistingStockSource = null, actor_config: ActorConfig = null, politics_config: PoliticsConfig = null,
		sim_config: SimConfig = null, facade_config: FacadeConfig = null) -> PoliticsHandle:
	var actors_cfg := actor_config if actor_config != null else ActorConfig.load_default()
	var economy_cfg := economy_config if economy_config != null else EconomyConfig.load_default()
	var politics_cfg := politics_config if politics_config != null else PoliticsConfig.load_default(actors_cfg)
	var ctx := PoliticsContext.create(actors_cfg, politics_cfg, economy_cfg, parcels)
	var problem := ctx.problem()
	if not problem.is_empty():
		push_error("PoliticsBootstrap: %s" % problem)
		return null
	var handle := PoliticsHandle.new()
	handle.context = ctx
	handle.economy = EconomySystem.create(parcels, economy_cfg, stock)
	handle.actors = ActorSystem.create(actors_cfg)
	handle.politics = PoliticsSystem.create(ctx)
	if handle.economy == null or handle.actors == null or handle.politics == null:
		return null
	var systems: Array[SimSystem] = [handle.economy, handle.actors, handle.politics]
	var handlers: Array[CommandHandler] = [AgendaRespondHandler.new(ctx)]
	handle.facade = SimFacadeImpl.create(world_seed, parcels, sim_config, facade_config, systems, handlers,
		PoliticsGate.new(ctx, handle.economy), PoliticsSnapshot.new(ctx))
	if handle.facade == null:
		return null
	PoliticsState.ensure_initialized(handle.facade.game_state(), ctx)  # tick 0'dan itibaren grup/meclis görünür
	return handle
