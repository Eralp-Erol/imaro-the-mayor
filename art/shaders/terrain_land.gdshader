// T-049b arazi kara yüzeyi: köşe rengi (palet) + dünya-uzayı ayrıntı (gürültü dokusu, UV = dünya x/z metre).
// Mat, GL Compatibility uyumlu: 3 doku okuması + birkaç smoothstep; kare-başı script işi yok. Parametreler veriden
// (data/view/terrain_look.json → TerrainLook). COLOR.a: 1 = kara yüzeyi, 0 = etek/duvar (ayrıntı uygulanmaz).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float scale_fine = 640.0;
uniform float scale_mid = 3200.0;
uniform float scale_patch = 5600.0;
uniform float patch_rot = 0.62;
uniform float tone_fine = 0.1;
uniform float tone_mid = 0.14;
uniform vec2 fine_fade = vec2(1500.0, 5000.0);

uniform vec3 dark_color : source_color = vec3(0.27, 0.36, 0.2);
uniform vec2 dark_threshold = vec2(0.58, 0.72);
uniform float dark_strength = 0.55;
uniform vec3 dry_color : source_color = vec3(0.62, 0.55, 0.34);
uniform vec2 dry_threshold = vec2(0.6, 0.74);
uniform float dry_strength = 0.5;
uniform float patch_max_slope = 24.0;
uniform float patch_max_height = 420.0;

uniform float sea_level = 0.0;
uniform vec3 sand_color : source_color = vec3(0.72, 0.65, 0.48);
uniform vec3 gravel_color : source_color = vec3(0.5, 0.46, 0.38);
uniform vec2 sand_height = vec2(2.5, 7.0);
uniform float gravel_height = 1.4;
uniform float coast_max_slope = 14.0;
uniform float coast_strength = 0.85;

uniform vec3 rock_color : source_color = vec3(0.5, 0.44, 0.34);
uniform vec3 rock_color_dark : source_color = vec3(0.38, 0.33, 0.26);
uniform vec2 rock_slope = vec2(30.0, 46.0);
uniform float rock_strength = 0.8;
uniform float strata_period = 22.0;
uniform float strata_amount = 0.1;

uniform vec3 haze_color : source_color = vec3(0.62, 0.68, 0.72);
uniform vec2 haze_range = vec2(6000.0, 40000.0);
uniform float haze_amount = 0.22;

// T-051 kent zemini: yapılı parsel maskesi (R = kaplama, G = sanayi/avlu); dünya x/z ile örneklenir. urban_rect.zw = 0
// ise (maske yok) hiçbir şey yapmaz. Yeni malzeme/draw call yok: aynı malzemede dördüncü doku okuması.
uniform sampler2D urban_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 urban_rect = vec4(0.0);
uniform vec3 urban_res_a : source_color = vec3(0.62, 0.57, 0.48);
uniform vec3 urban_res_b : source_color = vec3(0.54, 0.47, 0.37);
uniform vec3 urban_ind_a : source_color = vec3(0.56, 0.55, 0.52);
uniform vec3 urban_ind_b : source_color = vec3(0.48, 0.44, 0.38);
uniform float urban_strength = 0.94;
uniform vec2 urban_edge = vec2(0.3, 0.7);
uniform vec2 urban_sharp_fade = vec2(3000.0, 9000.0);
uniform vec2 urban_slope = vec2(22.0, 34.0);
uniform float urban_tone = 0.12;

varying vec2 v_xz;
varying float v_y;
varying float v_ny;
varying float v_shore;
uniform vec2 sand_shore = vec2(150.0, 500.0);

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_xz = UV;
	v_shore = UV2.x;
	v_y = VERTEX.y;
	v_ny = normalize(mat3(MODEL_MATRIX) * NORMAL).y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float mask = COLOR.a;
	float dist = length(VERTEX);
	vec2 rot_uv = vec2(cos(patch_rot) * v_xz.x - sin(patch_rot) * v_xz.y, sin(patch_rot) * v_xz.x + cos(patch_rot) * v_xz.y);
	vec2 s_mid = texture(noise_tex, v_xz / scale_mid).rg;
	vec2 s_patch = texture(noise_tex, rot_uv / scale_patch).ba;
	float n_fine = texture(noise_tex, v_xz / scale_fine).r;
	float fine_w = 1.0 - smoothstep(fine_fade.x, fine_fade.y, dist);

	// Eğim (yumuşak normalden) ve deniz üstü yükseklik.
	float slope_deg = degrees(acos(clamp(v_ny, 0.0, 1.0)));
	float h = v_y - sea_level;

	// Ton oynaması: iki ölçek; yakın ince katman uzakta kendiliğinden söner.
	float tone = 1.0 + (s_mid.x - 0.5) * 2.0 * tone_mid + (n_fine - 0.5) * 2.0 * tone_fine * fine_w;
	vec3 albedo = base * tone;

	// Bitki/çalı lekeleri: yalnız düz-alçak yerde; koyu orman-çalı ve kuru ot.
	float flat_ok = (1.0 - smoothstep(patch_max_slope * 0.6, patch_max_slope, slope_deg)) * (1.0 - smoothstep(patch_max_height * 0.7, patch_max_height, h));
	float dark_t = smoothstep(dark_threshold.x, dark_threshold.y, s_patch.x) * dark_strength * flat_ok;
	float dry_t = smoothstep(dry_threshold.x, dry_threshold.y, s_patch.y) * dry_strength * flat_ok;
	albedo = mix(albedo, dark_color * (0.9 + 0.2 * n_fine), dark_t);
	albedo = mix(albedo, dry_color * (0.92 + 0.16 * s_mid.y), dry_t * (1.0 - dark_t));

	// Dik yamaç kayası (eğime bağlı) + yatay tabaka çizgisi.
	float rock_t = smoothstep(rock_slope.x, rock_slope.y, slope_deg) * rock_strength;
	float strata = sin((v_y + (s_mid.y - 0.5) * 60.0) * 6.2831853 / strata_period) * strata_amount;
	vec3 rock = mix(rock_color_dark, rock_color, clamp(0.5 + strata * 3.0 + (n_fine - 0.5), 0.0, 1.0)) * (1.0 + strata);
	albedo = mix(albedo, rock, rock_t);

	// Kıyı: deniz seviyesinden yüksekliğe bağlı kum bandı (kıyı çizgisini yumuşakça izler) + çakıl çizgisi.
	float band_lo = sand_height.x * (0.6 + 0.8 * s_mid.y);
	float band_hi = sand_height.y * (0.6 + 0.8 * s_mid.y);
	float coast_flat = 1.0 - smoothstep(coast_max_slope * 0.5, coast_max_slope, slope_deg);
	float sand_t = (1.0 - smoothstep(band_lo, band_hi, h)) * coast_flat * coast_strength * (1.0 - smoothstep(sand_shore.x, sand_shore.y, v_shore));
	vec3 sand = mix(sand_color, gravel_color, (1.0 - smoothstep(0.0, gravel_height * (0.6 + 0.8 * n_fine), h)) * 0.9);
	albedo = mix(albedo, sand * (0.94 + 0.12 * n_fine), sand_t);

	// Kent zemini: yapılı parsel altında döşeme/avlu/toprak tonu (çim değil). Yakında maske eşikle keskinleşir,
	// uzakta (mip) doğrusal kalır: metroda kent lekesi kent rengini taşır.
	if (urban_rect.z > 0.0) {
		vec2 uu = (v_xz - urban_rect.xy) / urban_rect.zw;
		vec2 inside = step(vec2(0.0), uu) * step(uu, vec2(1.0));
		vec2 m = textureLod(urban_tex, uu, 0.0).rg;
		vec2 m_far = texture(urban_tex, uu).rg;
		float sharp = 1.0 - smoothstep(urban_sharp_fade.x, urban_sharp_fade.y, dist);
		float cover = mix(m_far.r, smoothstep(urban_edge.x, urban_edge.y, m.r), sharp) * inside.x * inside.y;
		float ind = mix(m_far.g, smoothstep(urban_edge.x, urban_edge.y, m.g), sharp);
		float ok = 1.0 - smoothstep(urban_slope.x, urban_slope.y, slope_deg);
		float k = clamp(cover * urban_strength * ok * mask, 0.0, 1.0);
		float pick = clamp(s_mid.y * 1.4 - 0.2 + (n_fine - 0.5) * 0.5 * fine_w, 0.0, 1.0);
		vec3 res_c = mix(urban_res_a, urban_res_b, pick);
		vec3 ind_c = mix(urban_ind_a, urban_ind_b, pick);
		vec3 ground = mix(res_c, ind_c, clamp(ind, 0.0, 1.0)) * (1.0 + (n_fine - 0.5) * 2.0 * urban_tone * fine_w);
		albedo = mix(albedo, ground, k);
	}

	// Uzak derinlik ipucu: mevcut ortamla uyumlu hafif hava tonu (ucuz; albedo karışımı).
	float haze_t = smoothstep(haze_range.x, haze_range.y, dist) * haze_amount;
	albedo = mix(albedo, haze_color, haze_t);

	ALBEDO = mix(base, albedo, mask);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
