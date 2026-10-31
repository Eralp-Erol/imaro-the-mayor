// T-050 yaşam belirtisi: yol parçası boyunca basit ileri akış (CPU'da kare başı örnek güncellemesi YOK).
// Örnek verisi (MultiMesh): transform = parça BAŞLANGICI + yaw (model +Z = yürüme yönü) + düzgün ölçek;
// INSTANCE_CUSTOM = (len, dy, bulge, packed): len parça yatay uzunluğu (m), dy parça sonu - başı yükseklik,
// bulge orta nokta sapması, packed = faz(10 bit) | hız(4 bit) << 10 | renk satırı(5 bit) << 14 (tam sayı, float32'de kesin).
// Konum d = mod(life_t * hız + faz * len, len); yükseklik ikinci derece profil + eğim kayması (araç/insan zemine oturur).
// Parça uçlarında küçülüp kaybolur; kamera mesafesi [life_range.x, life_range.y) dışında örnek çökertilir (LOD/menzil).

uniform float life_t = 0.0;
uniform vec3 life_cam = vec3(0.0);
uniform vec2 life_range = vec2(0.0, 1000.0);
uniform float life_speed = 7.5;
uniform float life_spread = 0.3;
uniform float life_end_fade = 3.0;

vec3 life_move(vec4 custom, mat4 model, vec3 vert) {
	float len = max(custom.x, 0.1);
	uint pk = uint(custom.w + 0.5);
	float phase = float(pk & 1023u) / 1024.0;
	float sq = float((pk >> 10u) & 15u) / 15.0;
	float spd = life_speed * (1.0 + life_spread * (sq * 2.0 - 1.0));
	float s = max(length(model[2].xyz), 0.0001);
	float d = mod(life_t * spd + phase * len, len);
	float t = d / len;
	float y = custom.y * t + 4.0 * custom.z * t * (1.0 - t);
	float slope = (custom.y + 4.0 * custom.z * (1.0 - 2.0 * t)) / len;
	float edge = min(d, len - d);
	float vis = clamp(edge / life_end_fade, 0.0, 1.0);
	vec3 centre = (model * vec4(0.0, y / s, d / s, 1.0)).xyz;
	float dist = distance(centre, life_cam);
	vis *= step(life_range.x, dist) * (1.0 - step(life_range.y, dist));
	vec3 v = vert * vis;
	v.y += y / s + slope * v.z;
	v.z += d / s;
	return v;
}
