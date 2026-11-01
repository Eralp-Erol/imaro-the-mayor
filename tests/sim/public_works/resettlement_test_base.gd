class_name ResettlementTestBase
extends "res://tests/sim/politics/reaction_world_base.gd"
## T-065 Aşama 1 ortak taban sınıfı (test paketi değildir). `ReactionWorldBase` kamulaştırma dünyası + yeniden iskân
## ayarları: yol DIAGONAL, parsel 1-3'ü alır (D1: 16 konut birimi yıkılır, 16 hane yerinden edilir;
## başlangıçta D1 420 hane / 22 konut, D2 407 hane / 8 konut).
## Yeniden iskân hedefi D2: testler D2'ye boş ev verir (bölge sütunu; BİNA yaratılmaz).
## Dünya köprüsü test ikizidir (parsel 1-3 köşegende; ikinci yol `SPUR` parsel 6'yı alır).

const SOURCE := "D1"
const TARGET := "D2"
const SPUR_TAKES: Array = [6]


## Yol işi yapılandırması: gerçek `data/` dosyası + `expropriation` ve `expropriation.resettlement` değişiklikleri.
func _works_config(resettlement: Dictionary = {}, expropriation: Dictionary = {}) -> PublicWorksConfig:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	(raw["expropriation"] as Dictionary).merge(expropriation, true)
	(raw["expropriation"]["resettlement"] as Dictionary).merge(resettlement, true)
	var cfg := PublicWorksConfig.from_dict(raw)
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	return cfg


## Taze dünya (yol yok): siyaset + bütçe bağlı; D2'ye `vacancy` boş ev (D2: bekleyen 40 hane, `40 + vacancy` konut).
## `vacancy` 0: D2'de boş ev yok (varsayılan dünya: 400 hane, 8 konut). İkinci yol parsel 6'yı alır.
func _rworld(vacancy: int = 0, resettlement: Dictionary = {}, expropriation: Dictionary = {}) -> Dictionary:
	var run := _world(false, Callable(), [], true, _works_config(resettlement, expropriation))
	(run["fake"] as FakeExpropriationWorld).take(P.spur_a_cm(), SPUR_TAKES)
	if vacancy > 0:
		_set_region(run, TARGET, 40, 40 + vacancy)
	return run


func _h(run: Dictionary) -> PoliticsHandle:
	return run["handle"]


func _f(run: Dictionary) -> SimFacadeImpl:
	return (run["handle"] as PoliticsHandle).facade as SimFacadeImpl


## Bölge sütunlarını doğrudan ayarlar (sim girdisi; yeni bina/birim YARATMAZ, mevcut sütunu seçilen değere çeker).
func _set_region(run: Dictionary, code: String, latent: int, res_built: int) -> void:
	var regions: Dictionary = EconomyState.data(_h(run).state())["regions"]
	var r := (regions["codes"] as PackedStringArray).find(code)
	var latent_col: PackedInt64Array = regions["latent_hh"]  # paylaşılan sütun: tür dönüşümü kopya yapar, yazmaz
	var built_col: PackedInt64Array = regions["res_built"]
	latent_col[r] = latent
	built_col[r] = res_built


func _latent(run: Dictionary, code: String) -> int:
	var regions: Dictionary = EconomyState.data(_h(run).state())["regions"]
	return (regions["latent_hh"] as PackedInt64Array)[(regions["codes"] as PackedStringArray).find(code)]


func _res_built(run: Dictionary, code: String) -> int:
	var regions: Dictionary = EconomyState.data(_h(run).state())["regions"]
	return (regions["res_built"] as PackedInt64Array)[(regions["codes"] as PackedStringArray).find(code)]


## Komut kabul edilmeli ve bir tick sonra uygulanmış olmalı.
func _do(run: Dictionary, command: SimCommand) -> CommandResult:
	var r := _f(run).submit_command(command)
	assert_bool(r.is_rejected()).override_failure_message("%s reddedildi: %s %s" % [command.kind, r.reason_key,
		str(r.args)]).is_false()
	_f(run).advance(1)
	return r


func _policy(run: Dictionary, enabled: bool = true) -> void:
	_do(run, SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, enabled))


func _road(run: Dictionary) -> void:
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))


func _spur(run: Dictionary) -> void:
	_do(run, SimCommand.public_work_road(P.spur_a_cm(), &"local", true))


## Son kamulaştıran yolun tahsis kaydı ({} = kayıt yok).
func _record(run: Dictionary, index: int = -1) -> Dictionary:
	var works := PublicWorksState.standing_roads(_h(run).state())
	var work: Dictionary = works[index if index >= 0 else works.size() - 1]
	return (work["expropriation"] as Dictionary).get("resettlement", {})


func _events(run: Dictionary, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in _f(run).events_since(0):
		if e.kind == kind:
			out.append(e)
	return out
