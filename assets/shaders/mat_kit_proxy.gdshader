shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// mat_kit_proxy (T-004 spec section 6): HLOD1/HLOD2 merged proxies. Albedo = vertex colour baked from the SAME
// palette (kit_palette.json), so LOD1 <-> HLOD swaps do not shift hue. The vertex colour is sRGB (as authored).

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
