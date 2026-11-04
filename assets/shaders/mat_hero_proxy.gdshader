shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// mat_hero_proxy (T-062 A3, ADR-0006 §3.1): HLOD1/HLOD2 birlesik mesh'ler. Albedo = kose rengi. Renk, onayli hero PROXY
// atlasindan YUKLEME ANINDA piskirilir (BuildingKit; ortalama dogrusal uzayda, kose rengi sRGB KODLU yazilir:
// kit mat_kit_proxy ile ayni sozlesme, renderer kose rengini cozer). Dogrusal yazilirsa iki kez cozulur ve HLOD
// dokulu kademeden belirgin koyu cikar (T-062 A3 yakalamasinda gozlendi).

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
