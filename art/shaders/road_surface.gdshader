// T-062 A4 yol yüzeyi: onaylı asfalt (new/worn) katmanları, dünya-xz örnekli (UV = dünya xz / tile_m), arazi ile AYNI
// sampler2DArray'i paylaşır (GroundLayerSet). Köşe rengi yüzey kodudur (RoadStyle.color_of): R = katman indeksi x 16/255,
// G = parlaklık / 2, B = kaldırım bandı (m) / 8. Köşe UV'si: x = eksene yanal ofset (m), y = yarım genişlik (m); y = 0
// (kavşak dolgusu) -> kaldırım yok. Kaldırım ek geometri değil: yol kesitinin kenarında sidewalk_cobble + koyu bordür.
// Aydınlatma arazi ile aynı (lambert): güneş/gölge uyumlu. GL Compatibility; kare-başı script yok.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2DArray layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m[16];
uniform float walk_layer = 1.0;
uniform float curb_m = 0.2;
uniform float curb_dark = 0.7;
uniform float detail_far = 400.0;
uniform vec2 fade_to_mean = vec2(900.0, 2600.0);
uniform vec3 haze_color : source_color = vec3(0.62, 0.68, 0.72);
uniform vec2 haze_range = vec2(6000.0, 40000.0);
uniform float haze_amount = 0.22;

varying vec2 v_xz;
varying vec2 v_lat;

void vertex() {
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	v_lat = UV;
}

// Katman örneği: yakında iki örnek (tile tekrarını kıran döndürülmüş çift), uzakta ortalama renk.
vec3 sample_surface(int id, vec2 gxz_x, vec2 gxz_y, float dist) {
	float inv = 1.0 / tile_m[id];
	vec2 uv = v_xz * inv;
	vec2 gx = gxz_x * inv;
	vec2 gy = gxz_y * inv;
	float fid = float(id);
	float far_t = smoothstep(fade_to_mean.x, fade_to_mean.y, dist);
	vec3 mean_c = textureLod(layers, vec3(uv, fid), 16.0).rgb;
	if (far_t >= 0.999) {
		return mean_c;
	}
	vec3 a = textureGrad(layers, vec3(uv, fid), gx, gy).rgb;
	if (dist < detail_far) {
		mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
		vec3 b = textureGrad(layers, vec3(rot * uv * 0.63 + vec2(0.37, 0.71), fid), rot * gx * 0.63, rot * gy * 0.63).rgb;
		float k = 1.0 - smoothstep(detail_far * 0.7, detail_far, dist);
		a = mix(a, b, 0.35 * k);
	}
	return mix(a, mean_c, far_t);
}

void fragment() {
	float dist = length(VERTEX);
	int id = int(floor(COLOR.r * 255.0 / 16.0 + 0.5));
	float brightness = COLOR.g * 2.0;
	float walk_m = COLOR.b * 8.0;
	vec2 gxz_x = dFdx(v_xz);
	vec2 gxz_y = dFdy(v_xz);
	vec3 col = sample_surface(id, gxz_x, gxz_y, dist);
	if (walk_m > 0.0 && v_lat.y > 0.0) {
		// kenara uzaklık (m): kesit kenarı = yarım genişlik
		float edge_d = v_lat.y - abs(v_lat.x);
		float w = 1.0 - smoothstep(walk_m - 0.08, walk_m + 0.08, edge_d);
		if (w > 0.0) {
			vec3 walk = sample_surface(int(walk_layer + 0.5), gxz_x, gxz_y, dist);
			col = mix(col, walk, w);
		}
		// bordür: kaldırım ile asfalt arasında ince koyu çizgi
		float curb = 1.0 - smoothstep(0.0, curb_m, abs(edge_d - walk_m));
		col *= mix(1.0, curb_dark, curb);
	}
	col *= brightness;
	float haze_t = smoothstep(haze_range.x, haze_range.y, dist) * haze_amount;
	col = mix(col, haze_color, haze_t);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
