class_name PoliticsTestBase
extends ActorTestBase
## tests/sim/politics ortak taban sınıfı (T-017). Kendi başına test paketi değildir (dosya adı `_test` ile bitmez).
## Siyaset verisini yapılandırma sınıfından BAĞIMSIZ okur (FileAccess + JSON), böylece bozuk-veri testleri
## doğrulayıcının kendisine güvenmeden kopya üzerinde düzenleme yapabilir. Koordinat/bölge kodu GÖMÜLMEZ:
## parseller WorldFixture
## bölgelerinden (F1/F2) okunur.

const E := preload("res://tests/sim/economy/economy_test_support.gd")
const POLITICS_DIR := "res://data/politics/"
const EVENTS_DIR := "res://data/politics/events/"
const POLITICS_FILES: Array[String] = ["cadence", "blocs", "council", "media", "authority", "events"]
const WEEK := 7
## Köklü bir kalabalık/destek senaryosu: F1 dar altyapı + büyük hane, F2 geniş altyapı (yatırım olur, yük artar).
const STRESS := {"F1": {"initial_households": 600, "infra_capacity_units": 140},
	"F2": {"initial_households": 300, "infra_capacity_units": 3000}}
const BLOC_HOUSED := "actor.bloc.1"
const BLOC_SEEKING := "actor.bloc.2"


## Ham siyaset dosyaları (float'lı) ve olay şablonları: {dosya: Dictionary, "templates": {kimlik: Dictionary}}.
static func raw_politics() -> Dictionary:
	var out := {}
	for file_name in POLITICS_FILES:
		out[file_name] = JSON.parse_string(FileAccess.get_file_as_string(POLITICS_DIR + file_name + ".json"))
	var templates := {}
	for template_id: String in out["events"]["templates"]:
		templates[template_id] = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_DIR + template_id + ".json"))
	out["templates"] = templates
	return out


static func raw_politics_text() -> String:
	var all := ""
	for file_name in POLITICS_FILES:
		all += FileAccess.get_file_as_string(POLITICS_DIR + file_name + ".json")
	for template_id: String in raw_politics()["templates"]:
		all += FileAccess.get_file_as_string(EVENTS_DIR + template_id + ".json")
	return all


func politics_config() -> PoliticsConfig:
	var cfg := PoliticsConfig.load_default(config())
	assert_bool(cfg.is_valid()).override_failure_message("varsayılan siyaset verisi geçersiz: %s" % cfg.error).is_true()
	return cfg


## Ham dosyaların kopyasına `edit` uygular, PoliticsConfig kurar (doğrulama sonucu cfg.error/errors'ta).
func pol_mutated(edit: Callable, actors: ActorConfig = null) -> PoliticsConfig:
	var files := raw_politics()
	edit.call(files)
	return PoliticsConfig.from_files(files, actors if actors != null else config())


## Geçerli, düzenlenmiş siyaset yapılandırması (geçersizse test düşer).
func pol_valid(edit: Callable, actors: ActorConfig = null) -> PoliticsConfig:
	var cfg := pol_mutated(edit, actors)
	assert_bool(cfg.is_valid()).override_failure_message("düzenlenmiş siyaset verisi geçersiz: %s" % cfg.error).is_true()
	return cfg


## Siyasi katmanlı facade. `economy_patch`: ekonomi yapılandırma yaması; `edit`: siyaset ham verisi düzenleyici.
func handle(economy_patch: Dictionary = {}, per_region: int = 6, world_seed: int = SEED,
		edit: Callable = Callable(), actors_edit: Callable = Callable()) -> PoliticsHandle:
	var actors := config() if not actors_edit.is_valid() else mutated(actors_edit)
	assert_bool(actors.is_valid()).override_failure_message(actors.error).is_true()
	var pol := politics_config() if not edit.is_valid() else pol_valid(edit, actors)
	var h := PoliticsBootstrap.create(world_seed, FacadeTestSupport.fixture_source(per_region), E.config(economy_patch),
		null, actors, pol)
	assert_object(h).override_failure_message("PoliticsBootstrap.create başarısız").is_not_null()
	return h


## Talep/altyapı baskılı dünya: `zone.mixed` imarı tüm parsellere önerilmiş (doğrudan yürürlük: meclis kapısı kapalı).
func stress_handle(per_region: int = 14, world_seed: int = SEED, edit: Callable = Callable()) -> PoliticsHandle:
	var direct := func(files: Dictionary) -> void:
		files["council"]["requires_council"]["zoning.propose"] = false
		if edit.is_valid():
			edit.call(files)
	var h := handle(E.regions(STRESS), per_region, world_seed, direct)
	var result := h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
	assert_bool(result.is_rejected()).override_failure_message(String(result.reason_key)).is_false()
	return h


func tick(h: PoliticsHandle, days: int) -> void:
	h.facade.advance(days)


## Siyasi durum (canlı kayıt; salt okunur kullanın).
func pol(h: PoliticsHandle) -> Dictionary:
	return PoliticsState.data(h.state())


func bloc_book(h: PoliticsHandle, key: String, book_name: String) -> Dictionary:
	return ActorStore.actor_ref(h.state(), key)["state"][book_name]


## Kesim defterlerini doğrudan yazar (mekanik testleri ekonomiyi dolanmadan sınar).
func set_books(h: PoliticsHandle, key: String, grievances: Dictionary, satisfaction: Dictionary) -> void:
	var astate: Dictionary = ActorStore.actor_ref(h.state(), key)["state"]
	astate["grievances"] = grievances.duplicate()
	astate["satisfaction"] = satisfaction.duplicate()


## Tek kesim taraması (haftalık sistem zamanını beklemeden).
func scan_blocs(h: PoliticsHandle) -> void:
	BlocEngine.scan(h.state(), h.context)


func view_of(h: PoliticsHandle, key: String) -> GroupReactionView:
	for g in h.facade.snapshot().group_reactions:
		if String(g.group.ref()) == key:
			return g
	return null


## Belirli türde olaylar.
func events_of(h: PoliticsHandle, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in h.facade.events_since(0):
		if e.kind == kind:
			out.append(e)
	return out


## Belirli karar anahtarlı gerekçeler (eskiden yeniye).
func reasons_of(h: PoliticsHandle, decision_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in h.state().reasons.find({"decision": decision_key}):
		out.append(rec)
	return out
