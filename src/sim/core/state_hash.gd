class_name StateHash
extends RefCounted
## Kanonik SHA-256 durum hash'i (T-900, TEK-01/TEK-02). Saf mantık: sahne, zaman, OS, rastgelelik yok.
##
## `StateHash.of(value)` değeri aşağıdaki kanonik bayt akışına çevirip SHA-256 hex (64 küçük harf) döndürür.
## Aynı mantıksal içerik => aynı hash; sözlük ekleme sırası, float metin gösterimi ve Packed dizi türü etkilemez.
##
## Bayt biçimi (tüm çok baytlı sayılar big-endian):
##   null    0x00
##   bool    0x01 + 1 bayt (0/1)
##   int     0x02 + int64
##   float   0x03 + IEEE-754 binary64 (8 bayt). Tüm NaN'lar tek kanonik bit örüntüsüne (0x7FF8000000000000)
##           çevrilir; -0.0, +0.0 olarak yazılır (== ile eşit oldukları için). +/-INF kendi bitleriyle yazılır.
##   String  0x04 + uint32 UTF-8 bayt sayısı + baytlar. StringName, String ile aynı değerdir (&"a" == "a").
##   Array   0x05 + uint32 eleman sayısı + elemanlar (sıra anlamlıdır)
##   Dictionary 0x06 + uint32 girdi sayısı + (anahtar, değer) çiftleri; çiftler anahtarın kanonik kodlamasının
##           hex dizgesine göre sıralanır (ekleme sırası etkilemez). Anahtarlar desteklenen herhangi bir türdür.
##   Packed{Byte,Int32,Int64}Array, Packed{Float32,Float64}Array, PackedStringArray: eşdeğer Array olarak kodlanır
##           (PackedInt32Array([1,2]) ile [1,2] aynı hash'i verir). Float32 elemanlar tam olarak double'a genişler.
##   Packed{Vector2,Vector3,Vector4,Color}Array: 0x07 + bileşen sayısı (1 bayt) + uint32 eleman sayısı
##           + her bileşen float kuralıyla (tür etiketi olmadan binary64). Düz Array'den farklıdır.
## Desteklenmeyen türler (Object/Node, Callable, Vector2 vb. tekil değerler, RID...) ve döngüsel yapılar
## `push_error` ile açık, yol bilgili bir mesajla reddedilir ve `of()` boş string "" döndürür.

const MAX_DEPTH := 128

const _TAG_NULL := 0x00
const _TAG_BOOL := 0x01
const _TAG_INT := 0x02
const _TAG_FLOAT := 0x03
const _TAG_STRING := 0x04
const _TAG_ARRAY := 0x05
const _TAG_DICT := 0x06
const _TAG_VECTOR_ARRAY := 0x07

const _NAN_BITS := 0x7FF8000000000000


## `value` için SHA-256 hex hash'i; desteklenmeyen değerde hata basar ve "" döndürür.
static func of(value: Variant) -> String:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	var failure := _write(buffer, value, 0)
	if not failure.is_empty():
		push_error("StateHash: %s" % failure.replace("@@", "root"))
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buffer.data_array)
	return ctx.finish().hex_encode()


# Hata varsa "unsupported ... at @@<yol>" metni, yoksa "" döndürür. Yol, çağrı yığını boyunca geriye doğru birikir.
static func _write(buffer: StreamPeerBuffer, value: Variant, depth: int) -> String:
	if depth > MAX_DEPTH:
		return "nesting deeper than %d (cyclic structure?) at @@" % MAX_DEPTH
	match typeof(value):
		TYPE_NIL:
			buffer.put_u8(_TAG_NULL)
		TYPE_BOOL:
			buffer.put_u8(_TAG_BOOL)
			buffer.put_u8(1 if value else 0)
		TYPE_INT:
			buffer.put_u8(_TAG_INT)
			buffer.put_64(value)
		TYPE_FLOAT:
			_write_float(buffer, value, true)
		TYPE_STRING, TYPE_STRING_NAME:
			_write_string(buffer, str(value))
		TYPE_ARRAY:
			return _write_array(buffer, value, depth)
		TYPE_DICTIONARY:
			return _write_dictionary(buffer, value, depth)
		# Packed scalar arrays are canonically equivalent to Array (see format contract), but converting a 30k
		# parcel column with Array(value) allocates tens of thousands of Variants on every state hash. Iterate
		# directly so the emitted bytes remain byte-for-byte identical without the temporary allocation.
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return _write_packed_scalar_array(buffer, value, depth)
		TYPE_PACKED_VECTOR2_ARRAY:
			_write_vector_array(buffer, value, 2)
		TYPE_PACKED_VECTOR3_ARRAY:
			_write_vector_array(buffer, value, 3)
		TYPE_PACKED_VECTOR4_ARRAY:
			_write_vector_array(buffer, value, 4)
		TYPE_PACKED_COLOR_ARRAY:
			_write_vector_array(buffer, value, 4)
		_:
			return "unsupported type %s at @@" % _type_name(value)
	return ""


static func _write_float(buffer: StreamPeerBuffer, value: float, with_tag: bool) -> void:
	if with_tag:
		buffer.put_u8(_TAG_FLOAT)
	if is_nan(value):
		buffer.put_u64(_NAN_BITS)
	elif value == 0.0:
		buffer.put_double(0.0)  # -0.0 da buraya girer; sabit +0.0 yazılır
	else:
		buffer.put_double(value)


static func _write_string(buffer: StreamPeerBuffer, value: String) -> void:
	var utf8 := value.to_utf8_buffer()
	buffer.put_u8(_TAG_STRING)
	buffer.put_u32(utf8.size())
	buffer.put_data(utf8)


static func _write_array(buffer: StreamPeerBuffer, value: Array, depth: int) -> String:
	buffer.put_u8(_TAG_ARRAY)
	buffer.put_u32(value.size())
	for i in value.size():
		var failure := _write(buffer, value[i], depth + 1)
		if not failure.is_empty():
			return failure.replace("@@", "@@[%d]" % i)
	return ""


## PackedByte/Int/Float/String arrays use the exact Array tag and element encoding by contract. Kept separate
## from `_write_array` solely to avoid materialising `Array(value)` for economy's columnar parcel state.
static func _write_packed_scalar_array(buffer: StreamPeerBuffer, value: Variant, _depth: int) -> String:
	buffer.put_u8(_TAG_ARRAY)
	buffer.put_u32(value.size())
	# These arrays are hot in the columnar economy state.  Do not route every
	# scalar through Variant dispatch: emit the same canonical Array element
	# representation directly.  (There are no unsupported scalar elements here.)
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY:
			for item: int in value as PackedByteArray:
				buffer.put_u8(_TAG_INT)
				buffer.put_64(item)
		TYPE_PACKED_INT32_ARRAY:
			for item: int in value as PackedInt32Array:
				buffer.put_u8(_TAG_INT)
				buffer.put_64(item)
		TYPE_PACKED_INT64_ARRAY:
			for item: int in value as PackedInt64Array:
				buffer.put_u8(_TAG_INT)
				buffer.put_64(item)
		TYPE_PACKED_FLOAT32_ARRAY:
			for item: float in value as PackedFloat32Array:
				_write_float(buffer, item, true)
		TYPE_PACKED_FLOAT64_ARRAY:
			for item: float in value as PackedFloat64Array:
				_write_float(buffer, item, true)
		TYPE_PACKED_STRING_ARRAY:
			for item: String in value as PackedStringArray:
				_write_string(buffer, item)
		_:
			return "unsupported packed scalar array at @@"
	return ""


static func _write_dictionary(buffer: StreamPeerBuffer, value: Dictionary, depth: int) -> String:
	# Save-state dictionaries use textual field names.  Their canonical byte order is
	# string length followed by UTF-8 bytes, so they can be ordered without allocating
	# a canonical scratch buffer for every field.  Keep the generic path below for the
	# public StateHash contract, whose dictionary keys may be any supported type.
	var textual_keys := true
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			textual_keys = false
			break
	if textual_keys:
		# Cache UTF-8 lengths once.  `sort_custom` can call its comparator many
		# times per record; repeated `to_utf8_buffer()` dominated reason-log hashes.
		var entries: Array = []  # [asıl anahtar, metin anahtar, UTF-8 bayt sayısı]
		for key: Variant in value.keys():
			var text := str(key)
			entries.append([key, text, text.to_utf8_buffer().size()])
		entries.sort_custom(func(a: Array, b: Array) -> bool:
			return a[2] < b[2] if a[2] != b[2] else a[1] < b[1])
		buffer.put_u8(_TAG_DICT)
		buffer.put_u32(entries.size())
		for entry: Array in entries:
			_write_string(buffer, entry[1])
			var text_value_failure := _write(buffer, value[entry[0]], depth + 1)
			if not text_value_failure.is_empty():
				return text_value_failure.replace("@@", "@@[%s]" % var_to_str(entry[0]))
		return ""
	# Only keys need a scratch buffer in order to establish canonical ordering.  Writing
	# each value into its own buffer and copying it again into `buffer` made deep event
	# and reason logs quadratic in temporary byte traffic.  Keep the exact byte format,
	# but encode values directly once their sorted keys are known.
	var entries: Array = []  # her biri [anahtar kodlaması (hex), anahtar baytları, asıl anahtar]
	for key: Variant in value.keys():
		var key_buffer := StreamPeerBuffer.new()
		key_buffer.big_endian = true
		var key_failure := _write(key_buffer, key, depth + 1)
		if not key_failure.is_empty():
			return key_failure.replace("@@", "@@{key %s}" % str(key))
		entries.append([key_buffer.data_array.hex_encode(), key_buffer.data_array, key])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	buffer.put_u8(_TAG_DICT)
	buffer.put_u32(entries.size())
	for entry: Array in entries:
		buffer.put_data(entry[1])
		var value_failure := _write(buffer, value[entry[2]], depth + 1)
		if not value_failure.is_empty():
			return value_failure.replace("@@", "@@[%s]" % var_to_str(entry[2]))
	return ""


static func _write_vector_array(buffer: StreamPeerBuffer, value: Variant, components: int) -> void:
	buffer.put_u8(_TAG_VECTOR_ARRAY)
	buffer.put_u8(components)
	buffer.put_u32(value.size())
	for element: Variant in value:
		if element is Color:
			var c: Color = element
			for component: float in [c.r, c.g, c.b, c.a]:
				_write_float(buffer, component, false)
		else:
			for i in components:
				_write_float(buffer, element[i], false)


static func _type_name(value: Variant) -> String:
	if value is Object:
		return "Object"
	return type_string(typeof(value))
