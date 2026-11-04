class_name EconomyBootstrap
extends RefCounted
## Ekonomi çekirdeğini `SimFacadeImpl.create(..., extra_systems, extra_handlers)` ile kurar (T-013). Varsayılan
## `SimFacadeImpl.create` ekonomiyi KURMAZ (mevcut davranış korunur); uygulama/entegrasyon bunu çağırır.


## Ekonomili facade. Geçersiz kurulumda push_error + null. `stock` boşsa stoksuz dünya.
static func create(world_seed: int, parcels: ParcelSource, config: EconomyConfig = null,
		stock: ExistingStockSource = null, sim_config: SimConfig = null, facade_config: FacadeConfig = null,
		extra_systems: Array[SimSystem] = [], extra_handlers: Array[CommandHandler] = []) -> EconomyHandle:
	var cfg := config if config != null else EconomyConfig.load_default()
	var system := EconomySystem.create(parcels, cfg, stock)
	if system == null:
		return null
	var systems: Array[SimSystem] = [system]
	systems.append_array(extra_systems)
	var facade := SimFacadeImpl.create(world_seed, parcels, sim_config, facade_config, systems, extra_handlers)
	if facade == null:
		return null
	var handle := EconomyHandle.new()
	handle.facade = facade
	handle.system = system
	handle.config = cfg
	return handle


static func create_facade(world_seed: int, parcels: ParcelSource, config: EconomyConfig = null,
		stock: ExistingStockSource = null) -> SimFacadeImpl:
	var handle := create(world_seed, parcels, config, stock)
	return null if handle == null else handle.facade
