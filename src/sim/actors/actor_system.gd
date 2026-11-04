class_name ActorSystem
extends SimSystem
## Aktör sistemi (T-016 ölçüt 3): `SimFacadeImpl.create(..., extra_systems)` ile kaydedilir. Kalıcı durum
## `state.systems["actors"]`'tadır (ActorStore); bu nesne durum tutmaz, yalnız doğrulanmış yapılandırmayı taşır.
## İlk günlük adımda aktör durumunu kadrodan kurar (kayıt yüklenmişse kurulu olanı sürdürür), sonra her tick
## dedikoduyu uygular ve aralıkta çürütür/budar (ActorMemory.advance). Rastgelelik: `rng.actors` akışının tohumundan
## türeyen anahtarlı çekilişler (ActorDecision.noise_draw).
## Karar ve olay uygulama, çağıran sistemlerin (T-017 siyasi aktörler, T-013 yatırımcılar) işidir: onlar
## `ActorDecision.evaluate` ve `ActorMemory.apply_event`i bu sistemden SONRA kayıtlı sistemlerde çağırır.

var _config: ActorConfig


## Doğrulanmış yapılandırmayla sistem; yapılandırma geçersizse push_error + null.
static func create(config: ActorConfig = null) -> ActorSystem:
	var cfg := config if config != null else ActorConfig.load_default()
	if not cfg.is_valid():
		push_error("ActorSystem: invalid ActorConfig (%s)" % cfg.error)
		return null
	var system := ActorSystem.new()
	system._config = cfg
	return system


func system_id() -> StringName:
	return ActorStore.SYSTEM


func config() -> ActorConfig:
	return _config


func on_daily(state: GameState) -> void:
	if ActorStore.ensure_initialized(state, _config):
		ActorMemory.advance(state, _config)
