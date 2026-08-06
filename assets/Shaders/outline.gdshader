shader_type spatial;
render_mode cull_front, unshaded;

uniform float outline_width : hint_range(0.0, 0.1) = 0.01;
uniform vec4 outline_color : source_color = vec4(0, 0, 0, 1);
uniform bool fade_with_distance = false;
uniform float fade_start : hint_range(1.0, 100.0) = 10.0;

void vertex() {
    vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    float dist_factor = 1.0;
    if (fade_with_distance) {
        float dist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
        dist_factor = clamp(dist / fade_start, 1.0, 3.0);
    }
    VERTEX += NORMAL * outline_width * dist_factor;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}