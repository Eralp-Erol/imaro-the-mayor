// T-062 A4 arazi kara yüzeyi: onaylı zemin katmanları (sampler2DArray; LibraryGate'ten, GroundLayerSet) + dünya-uzayı
// sınıf ağırlıkları. Tek malzeme, tek geçiş, GL Compatibility (emsal: T-055 zemin laboratuvarı).
// UV = dünya xz / tile_m (katman başına, `tile_m[]`). Köşe rengi (palet) yalnız UZAK solma ve etek içindir.
// Sınıf -> katman eşlemesi KODDA değil veride: data/view/terrain_look.json "ground.roles" -> `slot_layer[]`
// (rol sırası TerrainLook.GROUND_ROLES; aşağıdaki R_* sabitleriyle AYNI olmalı; test zorlar).
// COLOR.a: 1 = kara yüzeyi, 0 = etek/duvar. UV2.x = kıyı uzaklığı (m), UV2.y = tarla bölgesi ağırlığı [0, 1].
// Okuma: noise (4) + urban (1) + en çok iki katman x (1 + 1 yakında tile-bozucu) = 8-9 doku okuması/piksel.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m[16];
uniform float slot_layer[16];

uniform float scale_fine = 640.0;
uniform float scale_mid = 3200.0;
uniform float scale_patch = 5600.0;
uniform float scale_breaker = 96.0;
uniform float patch_rot = 0.62;
uniform float tone_fine = 0.1;
uniform float tone_mid = 0.14;
uniform vec2 fine_fade = vec2(1500.0, 5000.0);

// Katman seçimi / geçişi
uniform float base_weight = 0.5;
uniform float blend_width = 0.12;
uniform float edge_jitter = 0.12;
uniform float detail_far = 500.0;          // bu mesafeden sonra ikinci (tile-bozucu) örnek yok
uniform vec2 fade_to_mean = vec2(900.0, 2600.0);  // doku -> katman ortalama rengi (moiré yok)
uniform float far_base_mix = 0.3;          // uzakta köşe (sınıf) rengi payı
uniform vec2 far_base_range = vec2(2600.0, 9000.0);

// Doğal sınıflar
uniform vec2 dark_threshold = vec2(0.58, 0.72);
uniform float dark_strength = 0.65;
uniform vec2 dry_threshold = vec2(0.6, 0.74);
uniform float dry_strength = 0.5;
uniform float patch_max_slope = 24.0;
uniform float patch_max_height = 420.0;
uniform vec2 scrub_height = vec2(35.0, 150.0);
uniform vec2 scrub_slope = vec2(6.0, 15.0);
uniform float scrub_weight = 0.9;
uniform float green_bias = 0.42;           // nemli çayır cepleri: orta ölçek gürültü (s_mid.y) etrafında
uniform float green_gain = 2.0;
uniform vec2 grove_threshold = vec2(0.55, 0.72);  // zeytin/dut koruları: orta ölçek (s_mid.x) gürültü
uniform float grove_weight = 0.8;

uniform float sea_level = 0.0;
uniform vec2 sand_height = vec2(2.5, 7.0);
uniform vec2 sand_shore = vec2(150.0, 500.0);
uniform float gravel_height = 1.4;
uniform float coast_max_slope = 14.0;
uniform float coast_strength = 0.85;

uniform vec2 rock_slope = vec2(30.0, 46.0);
uniform float rock_strength = 0.8;

// Tarla mozaiği (palet ile aynı dönük dikdörtgen ızgara)
uniform float field_rot = 0.41;
uniform vec2 field_size = vec2(760.0, 480.0);
uniform vec2 field_threshold = vec2(0.3, 0.6);
uniform float field_share_a = 0.4;
uniform float field_share_b = 0.4;
uniform float field_edge_m = 10.0;

uniform vec3 haze_color : source_color = vec3(0.62, 0.68, 0.72);
uniform vec2 haze_range = vec2(6000.0, 40000.0);
uniform float haze_amount = 0.22;

// Kent zemini: yapılı parsel maskesi. R = kaplama, G = sanayi, B = döşeme (plaza) seçimi, A = yeşil seçimi
// (B/A kaplamayla çarpılı: gölgelendirici R'ye böler). urban_rect.zw = 0 ise (maske yok) hiçbir şey yapmaz.
uniform sampler2D urban_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 urban_rect = vec4(0.0);
uniform float urban_strength = 0.94;
uniform vec2 urban_edge = vec2(0.3, 0.7);
uniform vec2 urban_sharp_fade = vec2(3000.0, 9000.0);
uniform vec2 urban_slope = vec2(22.0, 34.0);
uniform vec2 walk_band = vec2(0.62, 0.95);  // kaplama kenarında kaldırım bandı (R eşiği)
uniform float walk_strength = 0.95;

// D-021 "Kuru ot ve toprak": kentin içindeki BOŞ arazi (yıkılan yol, boş belediye arazisi, boş parsel) düz hardal yerine
// sönük saman + çıplak toprak + soluk ot yamaları. Ek geometri/doku yok: aynı geçiş, 3 gürültü okuması + 1 maske okuması.
// "Kent içi" = yapılı-parsel maskesinin YÜKSEK mip'i (yakın çevrede yapı var); kırsal tarla/çayır etkilenmez.
uniform float vacant_strength = 0.9;                       // 0 = kapalı (karşılaştırma için)
uniform vec2 vacant_near = vec2(0.06, 0.3);                // yüksek mip kaplaması -> kent içi ağırlığı
uniform float vacant_lod = 5.0;
uniform vec3 vacant_straw : source_color = vec3(0.57, 0.52, 0.36);
uniform vec3 vacant_soil : source_color = vec3(0.47, 0.38, 0.28);
uniform vec3 vacant_sage : source_color = vec3(0.44, 0.46, 0.32);
uniform vec2 vacant_detail_fade = vec2(400.0, 1800.0);     // ince benek uzakta söner

varying vec2 v_xz;
varying float v_y;
varying float v_ny;
varying float v_shore;
varying float v_field;

const int R_DEFAULT = 0;
const int R_GREEN = 1;
const int R_SCRUB = 2;
const int R_OLIVE = 3;
const int R_ROCK = 4;
const int R_SAND = 5;
const int R_GRAVEL = 6;
const int R_FIELD_A = 7;
const int R_FIELD_B = 8;
const int R_FIELD_EDGE = 9;
const int R_PLAZA = 10;
const int R_UDIRT = 11;
const int R_UGREEN = 12;
const int R_UIND = 13;
const int R_WALK = 14;
const int ROLE_COUNT = 15;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_xz = UV;
	v_shore = UV2.x;
	v_field = UV2.y;
	v_y = VERTEX.y;
	v_ny = normalize(mat3(MODEL_MATRIX) * NORMAL).y;
}

// Rolün katmanı: yakında iki örnek (tile tekrarını kıran döndürülmüş çift), uzakta katman ORTALAMA rengi.
// Türevler dallanmanın DIŞINDA hesaplanır (textureGrad): tekdüze olmayan akışta türev tanımsızlığı yok.
vec3 sample_role(int role, vec2 xz, vec2 dxz_x, vec2 dxz_y, float mk, float dist) {
	int id = int(slot_layer[role] + 0.5);
	float inv = 1.0 / tile_m[id];
	vec2 uv = xz * inv;
	vec2 gx = dxz_x * inv;
	vec2 gy = dxz_y * inv;
	float fid = float(id);
	float far_t = smoothstep(fade_to_mean.x, fade_to_mean.y, dist);
	vec3 col;
	if (far_t >= 0.999) {
		return textureLod(layers, vec3(uv, fid), 16.0).rgb;
	}
	col = textureGrad(layers, vec3(uv, fid), gx, gy).rgb;
	if (dist < detail_far) {
		mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
		vec2 uv2 = rot * uv * 0.63 + vec2(0.37, 0.71);
		vec3 b = textureGrad(layers, vec3(uv2, fid), rot * gx * 0.63, rot * gy * 0.63).rgb;
		float k = smoothstep(0.3, 0.7, mk) * (1.0 - smoothstep(detail_far * 0.7, detail_far, dist));
		col = mix(col, b, 0.5 * k);
	}
	if (far_t > 0.0) {
		col = mix(col, textureLod(layers, vec3(uv, fid), 16.0).rgb, far_t);
	}
	return col;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float mask = COLOR.a;
	float dist = length(VERTEX);
	vec2 xz = v_xz;
	vec2 dxz_x = dFdx(xz);
	vec2 dxz_y = dFdy(xz);
	vec2 rot_uv = vec2(cos(patch_rot) * xz.x - sin(patch_rot) * xz.y, sin(patch_rot) * xz.x + cos(patch_rot) * xz.y);
	vec2 s_mid = texture(noise_tex, xz / scale_mid).rg;
	vec2 s_patch = texture(noise_tex, rot_uv / scale_patch).ba;
	float n_fine = texture(noise_tex, xz / scale_fine).r;
	float mk = texture(noise_tex, xz / scale_breaker).r;
	float fine_w = 1.0 - smoothstep(fine_fade.x, fine_fade.y, dist);

	float slope_deg = degrees(acos(clamp(v_ny, 0.0, 1.0)));
	float h = v_y - sea_level;

	float w[15];
	for (int i = 0; i < ROLE_COUNT; i++) { w[i] = 0.0; }

	// --- doğal sınıflar -------------------------------------------------------------------------------
	float flat_ok = (1.0 - smoothstep(patch_max_slope * 0.6, patch_max_slope, slope_deg)) * (1.0 - smoothstep(patch_max_height * 0.7, patch_max_height, h));
	float rock_t = smoothstep(rock_slope.x, rock_slope.y, slope_deg) * rock_strength;
	float coast_flat = 1.0 - smoothstep(coast_max_slope * 0.5, coast_max_slope, slope_deg);
	float band_lo = sand_height.x * (0.6 + 0.8 * s_mid.y);
	float band_hi = sand_height.y * (0.6 + 0.8 * s_mid.y);
	float sand_t = (1.0 - smoothstep(band_lo, band_hi, h)) * coast_flat * coast_strength * (1.0 - smoothstep(sand_shore.x, sand_shore.y, v_shore));
	float gravel_mix = (1.0 - smoothstep(0.0, gravel_height * (0.6 + 0.8 * n_fine), h)) * 0.9;
	float scrub_t = clamp(smoothstep(scrub_height.x, scrub_height.y, h + (s_mid.y - 0.5) * 110.0) + smoothstep(scrub_slope.x, scrub_slope.y, slope_deg) * 0.55, 0.0, 1.0);

	w[R_DEFAULT] = base_weight;
	float green_pocket = clamp(green_bias + (s_mid.y - 0.5) * green_gain + (n_fine - 0.5) * 0.35 * fine_w, 0.0, 0.95);
	w[R_GREEN] = max(smoothstep(dark_threshold.x, dark_threshold.y, s_patch.x) * dark_strength * 1.4, green_pocket) * flat_ok;
	w[R_OLIVE] = max(smoothstep(dry_threshold.x, dry_threshold.y, s_patch.y) * dry_strength * 1.6, smoothstep(grove_threshold.x, grove_threshold.y, s_mid.x) * grove_weight) * flat_ok;
	w[R_SCRUB] = scrub_t * scrub_weight * (1.0 - rock_t);
	w[R_ROCK] = rock_t;
	w[R_SAND] = sand_t * (1.0 - gravel_mix);
	w[R_GRAVEL] = sand_t * gravel_mix;

	// Tarla mozaiği: palet ile aynı dönük hücre; hücre karması: sürülmüş / anız / nadas (varsayılan zemin).
	float fw = smoothstep(field_threshold.x, field_threshold.y, v_field);
	if (fw > 0.0) {
		vec2 fp = vec2(cos(field_rot) * xz.x - sin(field_rot) * xz.y, sin(field_rot) * xz.x + cos(field_rot) * xz.y) / field_size;
		vec2 cell = floor(fp);
		vec2 fr = fp - cell;
		float r = hash21(cell);
		float is_a = step(r, field_share_a);
		float is_b = step(field_share_a, r) * step(r, field_share_a + field_share_b);
		float edge_m = min(min(fr.x, 1.0 - fr.x) * field_size.x, min(fr.y, 1.0 - fr.y) * field_size.y);
		float strip = 1.0 - smoothstep(field_edge_m * 0.5, field_edge_m, edge_m);
		float in_field = (is_a + is_b) * fw;
		w[R_FIELD_A] = is_a * fw * 0.95;
		w[R_FIELD_B] = is_b * fw * 0.95;
		w[R_FIELD_EDGE] = in_field * strip;
		// alan içi doğal sınıflar susar (tarla üstünde yamaç/kaya hariç)
		float quiet = 1.0 - in_field * (1.0 - rock_t);
		w[R_GREEN] *= quiet;
		w[R_OLIVE] *= quiet;
		w[R_SCRUB] *= quiet;
	}

	// --- kent zemini ---------------------------------------------------------------------------------
	float vac_k = 0.0;
	if (urban_rect.z > 0.0) {
		vec2 uu = (xz - urban_rect.xy) / urban_rect.zw;
		vec2 inside = step(vec2(0.0), uu) * step(uu, vec2(1.0));
		vec4 m = textureLod(urban_tex, uu, 0.0);
		vec4 m_far = texture(urban_tex, uu);
		float sharp = 1.0 - smoothstep(urban_sharp_fade.x, urban_sharp_fade.y, dist);
		float cover = mix(m_far.r, smoothstep(urban_edge.x, urban_edge.y, m.r), sharp) * inside.x * inside.y;
		vec4 mm = mix(m_far, m, sharp);
		float ok = 1.0 - smoothstep(urban_slope.x, urban_slope.y, slope_deg);
		float k = clamp(cover * urban_strength * ok * mask, 0.0, 1.0);
		float near_city = smoothstep(vacant_near.x, vacant_near.y, textureLod(urban_tex, uu, vacant_lod).r);
		vac_k = vacant_strength * near_city * inside.x * inside.y * ok * mask * (1.0 - k) * (1.0 - rock_t) * (1.0 - sand_t);
		if (k > 0.0) {
			float rr = max(mm.r, 0.02);
			float ind = clamp(mm.g / rr, 0.0, 1.0);
			float pl = clamp(mm.b / rr, 0.0, 1.0);
			float gr = clamp(mm.a / rr, 0.0, 1.0);
			float dirt = clamp(1.0 - pl - gr, 0.0, 1.0);
			float walk = k * walk_strength * (1.0 - smoothstep(walk_band.x, walk_band.y, mm.r));
			for (int i = 0; i < ROLE_COUNT; i++) { w[i] *= (1.0 - k); }
			float res = k * (1.0 - ind) * (1.0 - walk);
			w[R_PLAZA] = res * pl;
			w[R_UGREEN] = res * gr;
			w[R_UDIRT] = res * dirt;
			w[R_UIND] = k * ind * (1.0 - walk);
			w[R_WALK] = walk;
		}
	}

	// --- en baskın iki katman; aralarında dar, gürültüyle bozulmuş geçiş -------------------------------
	int i1 = 0; int i2 = 0;
	float v1 = -1.0; float v2 = -1.0;
	// Kenar bozucu yüksek frekanslı: uzakta söner (piksel gürültüsü/moiré yok).
	float jit = ((n_fine - 0.5) + (mk - 0.5)) * edge_jitter * (1.0 - smoothstep(fade_to_mean.x, fade_to_mean.y, dist));
	for (int i = 0; i < ROLE_COUNT; i++) {
		float bi = w[i] + jit * step(0.0001, w[i]);
		if (bi > v1) { v2 = v1; i2 = i1; v1 = bi; i1 = i; }
		else if (bi > v2) { v2 = bi; i2 = i; }
	}
	float t = clamp(0.5 + (v1 - v2) / (2.0 * blend_width), 0.0, 1.0);
	t = smoothstep(0.0, 1.0, t);
	if (v2 <= 0.0001) { t = 1.0; }
	vec3 col = sample_role(i1, xz, dxz_x, dxz_y, mk, dist);
	if (t < 0.999) {
		col = mix(sample_role(i2, xz, dxz_x, dxz_y, mk, dist), col, t);
	}

	// Ton oynaması: iki ölçek; yakın ince katman uzakta kendiliğinden söner (tile tekrarını gizler).
	float tone_n = s_mid.x * 0.4 + s_mid.y * 0.3 + s_patch.y * 0.3;   // farklı ölçekler: tekrar eden ızgara izi yok
	col *= 1.0 + (tone_n - 0.5) * 2.0 * tone_mid + (n_fine - 0.5) * 2.0 * tone_fine * fine_w;

	// Boş kent arazisi: kuru ot / toprak (D-021). Doku tanesi korunur (parlaklık), renk saman-toprak-ot yamalarına kayar.
	if (vac_k > 0.0) {
		float vb = texture(noise_tex, xz / 190.0).b;
		float vm = texture(noise_tex, xz / 34.0).g;
		float vt = texture(noise_tex, xz / 9.0).r;
		float dfade = 1.0 - smoothstep(vacant_detail_fade.x, vacant_detail_fade.y, dist);
		float soil_w = smoothstep(0.52, 0.80, vb * 0.55 + vm * 0.45) * 0.8;
		float sage_w = smoothstep(0.52, 0.72, 1.0 - vm) * (1.0 - soil_w);
		vec3 dc = mix(vacant_straw, vacant_soil, soil_w);
		dc = mix(dc, vacant_sage, sage_w * 0.5);
		dc *= 1.0 + (vt - 0.5) * 0.35 * dfade;
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		dc *= mix(0.88, 1.12, clamp(lum * 3.0, 0.0, 1.0));
		col = mix(col, dc, vac_k);
	}

	// Uzakta sınıf (köşe) rengine kısmi solma: bölge çeşitliliği taşınır, doku tekrarı/moiré yok.
	float base_t = smoothstep(far_base_range.x, far_base_range.y, dist) * far_base_mix;
	col = mix(col, srgb_to_linear(base), base_t);

	// Uzak derinlik ipucu: hafif hava tonu.
	float haze_t = smoothstep(haze_range.x, haze_range.y, dist) * haze_amount;
	col = mix(col, haze_color, haze_t);

	ALBEDO = mix(base, col, mask);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
