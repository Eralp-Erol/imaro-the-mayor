class_name PlayableTempo
extends RefCounted
## Oynanabilir sahnenin zaman hızı kararları (T-043B C, core-loop-v0 §3). OYUN/ZAMAN katmanı: hız sim durumunun parçası
## DEĞİL (TickDriver ayarıdır; kayıt/hash etkilenmez), testler sim tick sayısı üzerinden hızdan bağımsızdır.
##  - Başlangıç hızı "hızlı" (`SimFacade.SPEED_FAST`; çekirdek yapılandırma: 4 tick/sn, 1 tick = 1 sim günü), böylece
##    yol/plan sonrası ~100 günlük bekleme ~25 sn sürer. Platform sınırı (`max_game_speed`) tutulur.
##  - Yol onayı ya da plan yürürlüğünden sonra tek seferlik, kapatılabilir hız ipucu (`PlayableSpeedHint`).
## Gün sayacı gizlenmez: üst çubuktaki tarih ve alt yardımdaki "Gün N" HudRoot'tan gelir, bu sınıf onlara dokunmaz.

const START_SPEED := SimFacade.SPEED_FAST


## Başlangıç hızını ayarlar. İstenen basamak kapalıysa (platform sınırı) izinli en yüksek çalışan basamağa iner.
## Seçilen basamağı döndürür (ayarlanamadıysa mevcut hız).
static func apply_start_speed(facade: SimFacade, max_level: int = SimFacade.SPEED_FASTEST) -> int:
	var level := pick_start_level(facade.available_speeds(), max_level)
	if level != SimFacade.SPEED_PAUSED:
		facade.set_speed(level)
	return facade.speed()


## `available` içinde `START_SPEED` ve `max_level` ile sınırlı en yüksek ÇALIŞAN basamak; yoksa duraklat (0).
static func pick_start_level(available: PackedInt32Array, max_level: int) -> int:
	var best := SimFacade.SPEED_PAUSED
	for level in available:
		if level != SimFacade.SPEED_PAUSED and level <= mini(START_SPEED, max_level) and level > best:
			best = level
	return best


## Platform sınırı içindeki en yüksek çalışan basamak (yoksa 0).
static func top_level(available: PackedInt32Array, max_level: int) -> int:
	var best := SimFacade.SPEED_PAUSED
	for level in available:
		if level <= max_level and level > best:
			best = level
	return best


## Ipucu düğmesinin gideceği basamak: duraklatılmışsa başlangıç hızı, değilse bir üst basamak. Yukarı yer yoksa mevcut.
static func faster_than(current: int, available: PackedInt32Array, max_level: int) -> int:
	if current == SimFacade.SPEED_PAUSED:
		return pick_start_level(available, max_level)
	var best := current
	for level in available:
		if level <= max_level and level > current and (best == current or level < best):
			best = level
	return best


## HUD kurulunca çağrılır: başlangıç hızını verir ve hız ipucunu bağlar. Dönen düğüm HUD katmanının çocuğudur
## (ağaç sahibi; çağıranın tutması gerekmez).
static func attach(hud: HudRoot, facade: SimFacade, prefs: PlayableHintPrefs = null) -> PlayableSpeedHint:
	apply_start_speed(facade, hud.ctx.max_game_speed if hud.ctx != null else SimFacade.SPEED_FASTEST)
	return PlayableSpeedHint.attach(hud, facade, prefs)
