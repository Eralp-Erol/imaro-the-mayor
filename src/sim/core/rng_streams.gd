class_name RngStreams
extends RefCounted
## Sistem başına tohumlu RNG akışları (T-002, TEK-02). Her akış kendi `RandomNumberGenerator`'ıdır; tohum, dünya
## tohumu + akış kimliğinden SABİT bir fonksiyonla türetilir. Bu yüzden bir akışa ek çağrı başka akışı kaydırmaz ve
## akışlar tembel oluşturulsa da (ilk kullanımda) sıra bağımsızdır. Durum (seed + state) kayda ve hash'e girer.
##
## Kural: her sistem YALNIZ kendi akışını kullanır (kimlik = sistem kimliği); akış paylaşımı yasak.
## Türetim yalnız 32-bit karıştırma kullanır (64-bit işaretli taşma yok) => platformlar arası aynı sonuç (PLT-04).

const _MASK32 := 0xFFFFFFFF
const _FNV_PRIME := 16777619
const _FNV_BASIS_A := 0x811C9DC5
const _FNV_BASIS_B := 0x2C1B3C6D
const _MIX_MUL := 0x45D9F3B

var world_seed: int = 0
var _streams: Dictionary = {}  # String -> RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value


## Akışın RNG'si; ilk kullanımda türetilmiş tohumla oluşturulur.
func stream(id: StringName) -> RandomNumberGenerator:
	var key := String(id)
	if not _streams.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = derive_seed(world_seed, id)
		_streams[key] = rng
	return _streams[key]


func has_stream(id: StringName) -> bool:
	return _streams.has(String(id))


## {"world_seed": int, "streams": {ad: {"seed": int, "state": int}}}
func to_dict() -> Dictionary:
	var out := {}
	for key: String in _streams:
		var rng: RandomNumberGenerator = _streams[key]
		out[key] = {"seed": rng.seed, "state": rng.state}
	return {"world_seed": world_seed, "streams": out}


## `to_dict()` çıktısından kurar; biçim denetimi `validate_dict` ile ayrıca yapılır.
static func from_dict(data: Dictionary) -> RngStreams:
	var result := RngStreams.new(int(data["world_seed"]))
	var streams_in: Dictionary = data["streams"]
	for key: Variant in streams_in:
		var entry: Dictionary = streams_in[key]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(entry["seed"])
		rng.state = int(entry["state"])  # tohumdan SONRA; seed atamak state'i sıfırlar
		result._streams[str(key)] = rng
	return result


## Biçim hatası metni; geçerliyse "".
static func validate_dict(data: Variant) -> String:
	if not (data is Dictionary):
		return "rng bölümü sözlük değil"
	if typeof(data.get("world_seed", null)) != TYPE_INT:
		return "rng.world_seed int değil"
	var streams_in: Variant = data.get("streams", null)
	if not (streams_in is Dictionary):
		return "rng.streams sözlük değil"
	for key: Variant in streams_in:
		var entry: Variant = streams_in[key]
		if not (entry is Dictionary) or typeof(entry.get("seed", null)) != TYPE_INT \
				or typeof(entry.get("state", null)) != TYPE_INT:
			return "rng.streams.%s {seed:int, state:int} değil" % str(key)
	return ""


## Akış tohumu: dünya tohumu + akış adı. Her zaman 0..2^63-1 aralığında. Sürümler arası SABİT kalmalı (kayıtlar).
static func derive_seed(world_seed_value: int, id: StringName) -> int:
	var bytes := String(id).to_utf8_buffer()
	var ws_lo := world_seed_value & _MASK32
	var ws_hi := (world_seed_value >> 32) & _MASK32
	var a := _fnv32(bytes, _FNV_BASIS_A)
	var b := _fnv32(bytes, _FNV_BASIS_B)
	var lo := _mix32(a ^ _mix32(ws_lo ^ 0x9E3779B9) ^ ws_hi)
	var hi := _mix32(b ^ _mix32(ws_hi ^ 0x85EBCA6B) ^ ws_lo) & 0x7FFFFFFF
	return (hi << 32) | lo


static func _fnv32(bytes: PackedByteArray, basis: int) -> int:
	var h := basis
	for byte in bytes:
		h = ((h ^ byte) * _FNV_PRIME) & _MASK32
	return h


static func _mix32(value: int) -> int:
	var x := value & _MASK32
	x = (((x >> 16) ^ x) * _MIX_MUL) & _MASK32
	x = (((x >> 16) ^ x) * _MIX_MUL) & _MASK32
	return ((x >> 16) ^ x) & _MASK32
