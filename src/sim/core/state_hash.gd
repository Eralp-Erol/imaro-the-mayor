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
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return _write_array(buffer, Array(value), depth)
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


static func _write_dictionary(buffer: StreamPeerBuffer, value: Dictionary, depth: int) -> String:
	var entries: Array = []  # her biri [anahtar kodlaması (hex), anahtar baytları, değer baytları]
	for key: Variant in value.keys():
		var key_buffer := StreamPeerBuffer.new()
		key_buffer.big_endian = true
		var key_failure := _write(key_buffer, key, depth + 1)
		if not key_failure.is_empty():
			return key_failure.replace("@@", "@@{key %s}" % str(key))
		var value_buffer := StreamPeerBuffer.new()
		value_buffer.big_endian = true
		var value_failure := _write(value_buffer, value[key], depth + 1)
		if not value_failure.is_empty():
			return value_failure.replace("@@", "@@[%s]" % var_to_str(key))
		entries.append([key_buffer.data_array.hex_encode(), key_buffer.data_array, value_buffer.data_array])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	buffer.put_u8(_TAG_DICT)
	buffer.put_u32(entries.size())
	for entry: Array in entries:
		buffer.put_data(entry[1])
		buffer.put_data(entry[2])
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
