shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// mat_hero_variety (D-021): onayli hero atlasi + ORNEK BASINA cati/cephe varyanti. Mesh ve atlas degismez.
// MultiMesh ozel verisi (INSTANCE_CUSTOM): x = cati modu (0 kiremit, 1 beton, 2 cinko), y = acik cephe (0/1),
// z = parlaklik sapmasi. Cati = egimli yuzey (dunya normali Y 0,5..0,985); duz catilar ve saçak alti degismez.
// Matematik BuildingVariety.recolor (HLOD1 koseleri) ile ayni; sabitler uniform olarak veriden gelir.

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 roof_concrete : source_color = vec3(0.61, 0.59, 0.55);
uniform vec3 roof_zinc : source_color = vec3(0.49, 0.51, 0.53);
uniform vec3 wall_light : source_color = vec3(0.89, 0.86, 0.79);
uniform float wall_light_mix = 0.6;

varying vec3 v_custom;
varying float v_up;
varying float v_y;

void vertex() {
	v_custom = INSTANCE_CUSTOM.xyz;
	v_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	v_y = VERTEX.y;
}

void fragment() {
	vec3 c = texture(atlas, UV).rgb * albedo_tint.rgb;
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mode = floor(v_custom.x + 0.5);
	bool pitched = v_up > 0.5 && v_up < 0.985;
	if (pitched && mode > 0.5) {
		vec3 base = mode < 1.5 ? roof_concrete : roof_zinc;
		c = base * clamp(0.55 + lum * 1.6, 0.45, 1.15);
	} else if (abs(v_up) < 0.5 && v_custom.y > 0.5) {
		float w = smoothstep(3.0, 4.5, v_y) * wall_light_mix * smoothstep(0.02, 0.1, lum);
		c = mix(c, wall_light * clamp(0.7 + lum * 0.9, 0.7, 1.1), w);
	}
	ALBEDO = c * (1.0 + v_custom.z);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
