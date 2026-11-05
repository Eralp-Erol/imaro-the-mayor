class_name DrawerModel
extends RefCounted
## Alttan çıkan çekmece (D-021): SAF mantık (düğüm yok, test edilebilir). Üç konum: KAPALI (yalnız tutamaç + başlık
## şeridi görünür; panel kapanmış sayılmaz), YARI (karar + birincil eylem görünür), TAM (uzun içerik). Parmakla
## sürükleme bırakılınca en yakın konuma oturur; hızlı fırlatma yönüne bir konum atlar. Şehri örten tüm gerçek
## paneller (imar, bütçe, meclis, gündem, politika, sonuç, nedensellik, denetçi, yol) aynı bileşeni kullanır.

enum State { CLOSED, HALF, FULL }

## Bu hızın (px/sn) üstündeki bırakma fırlatma sayılır (iPad parmak hızı ~ 500-3000).
const FLING_SPEED := 650.0


## Bir konum yukarı (daha açık). TAM'da kalır.
static func up_from(state: State) -> State:
	return State.FULL if state == State.HALF or state == State.FULL else State.HALF


## Bir konum aşağı (daha kapalı). KAPALI'da kalır.
static func down_from(state: State) -> State:
	return State.CLOSED if state == State.HALF or state == State.CLOSED else State.HALF


static func can_go_up(state: State) -> bool:
	return state != State.FULL


static func can_go_down(state: State) -> bool:
	return state != State.CLOSED


## Bırakma: `height` o anki çekmece yüksekliği, `heights` konum yükseklikleri (State -> float), `velocity_y` ekran
## Y hızı (negatif = yukarı), `from_state` sürükleme başındaki konum. Fırlatmada başlangıçtan bir konum atlar; aksi
## halde en yakın yüksekliğe oturur.
static func snap(height: float, heights: Dictionary, velocity_y: float, from_state: State) -> State:
	if absf(velocity_y) >= FLING_SPEED:
		return up_from(from_state) if velocity_y < 0.0 else down_from(from_state)
	var best := State.HALF
	var best_d := INF
	for s: State in [State.CLOSED, State.HALF, State.FULL]:
		var d := absf(float(heights.get(s, 0.0)) - height)
		if d < best_d:
			best_d = d
			best = s
	return best


## Sürüklenen yüksekliği [kapalı, tam] aralığına kenetler.
static func clamp_height(height: float, heights: Dictionary) -> float:
	return clampf(height, float(heights.get(State.CLOSED, 0.0)), float(heights.get(State.FULL, height)))
