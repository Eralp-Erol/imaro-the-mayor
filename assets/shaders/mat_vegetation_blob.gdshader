shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// mat_vegetation_blob (T-062 B1, ADR-0006 s4, T-057 Karar 5): hucre lekesi (HLOD). Albedo = kume kose rengi (sRGB KODLU,
// mat_hero_proxy ile ayni sozlesme). Bu mesh'in tek isi 400 m OTESINI temsil etmektir: yakin kademe (LOD0/LOD1 ag
// agaclari) kamera uzakligina gore ornek basina secilir, bu yuzden leke fragmanlari `begin_m`den YAKINSA atilir (sert
// kesim, kume hucre/parca merkezine bagli degil). Uzak uc: `fade_begin_m`..`end_m` arasi ekran-uzayi dither ile sonar
// (alfa karisimi yok; Compatibility'de siralama sorunu yok). Mesafe = goruntu uzayinda fragman uzakligi (kamera orijin).

uniform float begin_m = 400.0;
// Yakin uc: begin_m +- near_fade_m arasi ekran-uzayi dither ile belirir (B-5: 360-440 m caprazlama; agaclar 400 m'de biter).
uniform float near_fade_m = 40.0;
uniform float fade_begin_m = 1400.0;
uniform float end_m = 2200.0;

// 4x4 Bayer esik matrisi (0..1)
float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	float d = length(VERTEX);
	float near_t = smoothstep(begin_m - near_fade_m, begin_m + near_fade_m, d);
	if (near_t <= bayer4(FRAGCOORD.xy)) {
		discard;
	}
	float fade = smoothstep(fade_begin_m, end_m, d);
	if (fade > 0.0 && fade >= bayer4(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
