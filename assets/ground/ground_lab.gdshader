// T-055 zemin LAB gölgelendiricisi (oyuna bağlı DEĞİL). Tek malzeme, tek geçiş, GL Compatibility.
// Okuma: ctrl (1) + macro (1) + en çok iki katman x iki örnek (4, tile-bozucu çift örnek) = 6 doku okuması / piksel.
// Katman ağırlıkları ALU'da: kontrol haritası (asfalt/taş/tarla) + eğim + yükseklik + makro gürültü. En baskın 2 katman seçilir,
// aralarında yalnız dar bir geçiş (el boyası, bulanık değil); kenar makro gürültüyle bozulur.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2DArray layers : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ctrl_tex : filter_linear_mipmap, repeat_disable;
uniform float tile_m[14];
uniform vec2 ctrl_origin = vec2(-100.0, -100.0);
uniform float ctrl_size = 200.0;
uniform float macro_period = 96.0;
uniform float detail_far = 220.0; // bu mesafeden sonra ikinci (tile-bozucu) örnek atlanır
uniform float blend_width = 0.12;

varying vec3 v_pos;
varying vec3 v_nrm;

const int L_PLAZA = 0;
const int L_WALK = 1;
const int L_ASPH_NEW = 2;
const int L_ASPH_WORN = 3;
const int L_DIRT = 4;
const int L_GRASS_DRY = 5;
const int L_GRASS_GREEN = 6;
const int L_MAQUIS = 7;
const int L_OLIVE = 8;
const int L_PLOWED = 9;
const int L_STUBBLE = 10;
const int L_SAND = 11;
const int L_GRAVEL = 12;
const int L_ROCK = 13;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 sample_layer(int id, vec2 xz, float mk, float dist) {
	float tm = tile_m[id];
	vec2 uv = xz / tm;
	vec3 a = texture(layers, vec3(uv, float(id))).rgb;
	if (dist > detail_far) {
		return a;
	}
	// ikinci örnek: döndürülmüş + farklı ölçek; makro maskeyle karıştır -> tekrar deseni kırılır
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.63 + vec2(0.37, 0.71);
	vec3 b = texture(layers, vec3(uv2, float(id))).rgb;
	float k = smoothstep(0.3, 0.7, mk) * (1.0 - smoothstep(detail_far * 0.7, detail_far, dist));
	return mix(a, b, 0.5 * k + 0.0);
}

void fragment() {
	vec3 P = v_pos;
	vec2 xz = P.xz;
	float dist = length(VERTEX);
	vec4 mc = texture(macro_tex, xz / macro_period);
	vec4 mc2 = texture(macro_tex, xz / 13.0);   // orta ölçek (kenar bozucu / yama)
	vec4 mc3 = texture(macro_tex, xz / 3.1);    // ince ölçek (kenar kırığı)
	float slope = degrees(acos(clamp(normalize(v_nrm).y, 0.0, 1.0)));
	float h = P.y;

	// --- kontrol haritası (bilineer + eşik keskinleştirme, kenar kırıkları)
	vec2 cuv = (xz - ctrl_origin) / ctrl_size;
	vec4 c = texture(ctrl_tex, cuv);
	float inside = step(0.0, cuv.x) * step(cuv.x, 1.0) * step(0.0, cuv.y) * step(cuv.y, 1.0);
	float jit = (mc3.r - 0.5) * 0.18;
	float s_r = smoothstep(0.42, 0.58, c.r + jit * 0.3) * inside;
	float s_g = smoothstep(0.42, 0.58, c.g + jit * 0.3) * inside;
	float s_a = smoothstep(0.42, 0.58, c.a + jit) * inside;
	float cov = max(c.r + c.g + c.a, 0.001);
	float typ = clamp(c.b / cov, 0.0, 1.0);
	typ = smoothstep(0.45, 0.55, typ);
	float urban = max(s_r, s_g);

	float w[14];
	for (int i = 0; i < 14; i++) { w[i] = 0.0; }

	// asfalt (yeni/eskimiş) ve taş
	float worn = max(typ * s_r, smoothstep(0.62, 0.8, mc2.g) * 0.9 * s_r * (1.0 - typ));
	w[L_ASPH_NEW] = s_r * (1.0 - worn);
	w[L_ASPH_WORN] = s_r * worn;
	w[L_PLAZA] = s_g * typ;
	w[L_WALK] = s_g * (1.0 - typ);
	// tarla
	w[L_PLOWED] = s_a * (1.0 - typ);
	w[L_STUBBLE] = s_a * typ;

	// doğal zemin (kentsel/tarla olmayan alan)
	float nat = clamp(1.0 - max(urban, s_a), 0.0, 1.0);
	float nz = (mc.g - 0.5) * 2.0;       // -1..1 büyük ölçek
	float nz2 = (mc2.r - 0.5) * 2.0;
	float steep = smoothstep(31.0 + nz2 * 4.0, 40.0 + nz2 * 4.0, slope);
	float coast = (1.0 - smoothstep(1.6 + nz2 * 0.6, 2.7 + nz2 * 0.6, h)) * (1.0 - smoothstep(9.0, 15.0, slope));
	float gravel_t = (1.0 - smoothstep(0.05, 0.75 + nz2 * 0.3, h)) * coast;
	float mid_slope = smoothstep(9.0, 16.0, slope) * (1.0 - steep);
	float high = smoothstep(14.0 + nz * 5.0, 26.0 + nz * 5.0, h);
	float maq = clamp(mid_slope * 0.9 + high * 0.8 * (1.0 - steep) + smoothstep(0.58, 0.8, mc.b) * 0.5 * (1.0 - steep), 0.0, 1.0);
	float olive = (1.0 - steep) * smoothstep(3.0, 7.0, h) * (1.0 - smoothstep(14.0, 22.0, h)) * smoothstep(0.35, 0.65, mc.r) * (1.0 - maq * 0.8);
	float green = smoothstep(0.66, 0.85, mc2.b) * 0.8 * (1.0 - smoothstep(10.0, 18.0, slope)) * (1.0 - coast);
	float dirt = smoothstep(0.72, 0.88, mc.a) * (1.0 - smoothstep(10.0, 18.0, slope)) * (1.0 - coast) * 0.9;
	float rest = clamp(1.0 - coast - steep - maq - olive - green - dirt, 0.05, 1.0);
	w[L_ROCK] = steep * nat;
	w[L_SAND] = (coast * (1.0 - gravel_t)) * nat * (1.0 - steep);
	w[L_GRAVEL] = gravel_t * nat * (1.0 - steep);
	w[L_MAQUIS] += maq * nat * (1.0 - steep) * (1.0 - coast);
	w[L_OLIVE] += olive * nat * (1.0 - coast);
	w[L_GRASS_GREEN] += green * nat;
	w[L_DIRT] += dirt * nat + 0.0;
	w[L_GRASS_DRY] += rest * nat * (1.0 - steep);
	// tarla parsel kenarında toprak yıpranması
	w[L_DIRT] += (1.0 - s_a) * smoothstep(0.1, 0.4, c.a) * 0.9;

	// en baskın iki katman (kenar kırığı: ince ölçek bias)
	int i1 = 0; int i2 = 0;
	float v1 = -1.0; float v2 = -1.0;
	for (int i = 0; i < 14; i++) {
		float bi = w[i] + (mc3.g - 0.5) * 0.12 * step(0.0001, w[i]);
		if (bi > v1) { v2 = v1; i2 = i1; v1 = bi; i1 = i; }
		else if (bi > v2) { v2 = bi; i2 = i; }
	}
	float t = clamp(0.5 + (v1 - v2) / (2.0 * blend_width), 0.0, 1.0);
	t = smoothstep(0.0, 1.0, t);
	if (v2 <= 0.0001) { t = 1.0; }

	vec3 col1 = sample_layer(i1, xz, mc.r, dist);
	vec3 col = col1;
	if (t < 0.999) {
		vec3 col2 = sample_layer(i2, xz, mc.r, dist);
		col = mix(col2, col1, t);
	}

	// makro ton oynaması (tile tekrarını gizler; doğal alanda daha güçlü, kentsel alanda sakin)
	float tone = 1.0 + (mc.a - 0.5) * mix(0.30, 0.10, urban) + (mc2.a - 0.5) * 0.10;
	col *= tone;
	// hafif yamaç koyulaşması (el boyası derinlik)
	col *= 1.0 - smoothstep(20.0, 40.0, slope) * 0.08;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
