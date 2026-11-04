shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D object_normals : filter_linear_mipmap_anisotropic;
uniform vec4 map_u_0;
uniform vec4 map_v_0;
uniform vec4 bounds_0;
uniform vec4 map_u_1;
uniform vec4 map_v_1;
uniform vec4 bounds_1;
uniform vec4 map_u_2;
uniform vec4 map_v_2;
uniform vec4 bounds_2;
uniform vec2 normal_data_offset_px;
uniform vec2 normal_data_size_px;
varying vec3 object_position;

void vertex() {
    object_position = VERTEX;
}

void projection_sample(vec3 p, vec3 camera_direction, vec3 pixel_right, vec3 pixel_up,
        vec4 u, vec4 v, vec4 bounds, out vec4 rgba, out vec3 normal, out float weight) {
    vec2 uv = vec2(dot(u, vec4(p, 1.0)), dot(v, vec4(p, 1.0)));
    bool inside = all(greaterThanEqual(uv, bounds.xy)) && all(lessThanEqual(uv, bounds.zw));
    // Canonical camera-plane footprint, independent of the receiving card/derivatives.
    vec2 dx = vec2(dot(u.xyz, pixel_right), dot(v.xyz, pixel_right)) * 1024.0;
    vec2 dy = vec2(dot(u.xyz, pixel_up), dot(v.xyz, pixel_up)) * 1024.0;
    float lod = max(0.0, log2(max(max(length(dx), length(dy)), 0.000001)));
    vec2 address = clamp(uv, bounds.xy, bounds.zw);
    rgba = textureLod(atlas, address, lod);
    vec2 data_uv = (address * 1024.0 - normal_data_offset_px) / normal_data_size_px;
    normal = textureLod(object_normals, data_uv, lod).rgb * 2.0 - 1.0;
    bool valid = inside && dot(normal, normal) >= 0.0025;
    if (valid) {
        normal = normalize(normal);
        if (dot(normal, camera_direction) < 0.0) {
            normal = -normal;
        }
    }
    vec3 axis = normalize(cross(u.xyz, v.xyz));
    float directional = dot(camera_direction, axis);
    weight = valid ? directional * directional * rgba.a : 0.0;
}

void fragment() {
    mat3 world_to_object = inverse(mat3(MODEL_MATRIX));
    vec3 camera_object = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
    vec3 c = normalize(camera_object - object_position);
    vec3 view_position = (VIEW_MATRIX * MODEL_MATRIX * vec4(object_position, 1.0)).xyz;
    float depth_scale = abs(PROJECTION_MATRIX[3][3]) > 0.5 ? 1.0 : abs(view_position.z);
    float pixel_world = 2.0 * depth_scale / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
    vec3 pixel_right = world_to_object * INV_VIEW_MATRIX[0].xyz * pixel_world;
    vec3 pixel_up = world_to_object * INV_VIEW_MATRIX[1].xyz * pixel_world;
    vec4 color0; vec4 color1; vec4 color2;
    vec3 normal0; vec3 normal1; vec3 normal2;
    float w0; float w1; float w2;
    projection_sample(object_position, c, pixel_right, pixel_up, map_u_0, map_v_0, bounds_0, color0, normal0, w0);
    projection_sample(object_position, c, pixel_right, pixel_up, map_u_1, map_v_1, bounds_1, color1, normal1, w1);
    projection_sample(object_position, c, pixel_right, pixel_up, map_u_2, map_v_2, bounds_2, color2, normal2, w2);
    float total = w0 + w1 + w2;
    vec3 best_normal = w0 >= w1 && w0 >= w2 ? normal0 : (w1 >= w2 ? normal1 : normal2);
    vec3 best_color = w0 >= w1 && w0 >= w2 ? color0.rgb : (w1 >= w2 ? color1.rgb : color2.rgb);
    vec3 object_normal;
    vec3 shared_color;
    if (total <= 0.000001) {
        if (max(max(w0, w1), w2) <= 0.0) {
            discard;
        }
        object_normal = best_normal;
        shared_color = best_color;
    } else {
        object_normal = normal0 * w0 + normal1 * w1 + normal2 * w2;
        shared_color = (color0.rgb * w0 + color1.rgb * w1 + color2.rgb * w2) / total;
    }
    if (dot(object_normal, object_normal) < 0.000001) {
        object_normal = best_normal;
    }
    ALBEDO = shared_color;
    NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * normalize(object_normal), 0.0)).xyz);
    // Own card identity selects ONLY its original source alpha, already among the six fetches.
    ALPHA = color0.a;
    if (all(greaterThanEqual(UV, bounds_1.xy)) && all(lessThanEqual(UV, bounds_1.zw))) {
        ALPHA = color1.a;
    } else if (all(greaterThanEqual(UV, bounds_2.xy)) && all(lessThanEqual(UV, bounds_2.zw))) {
        ALPHA = color2.a;
    }
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
