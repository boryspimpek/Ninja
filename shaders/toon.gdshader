shader_type spatial;
render_mode diffuse_toon, specular_toon;

group_uniforms Albedo;
uniform sampler2D albedo_texture : source_color;
uniform vec4 albedo_color : source_color = vec4(1.0);

group_uniforms Toon_Bands;
uniform int toon_steps : hint_range(1, 8) = 3;
uniform float shadow_min : hint_range(0.0, 1.0) = 0.15; // jak ciemny może być cień
uniform float band_softness : hint_range(0.0, 0.5) = 0.02; // rozmycie granicy pasm

group_uniforms Rim_Light;
uniform bool enable_rim = false;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec4 rim_color : source_color = vec4(1.0);

group_uniforms Specular;
uniform bool enable_specular = false;
uniform float specular_size : hint_range(0.0, 1.0) = 0.1;

void fragment() {
    vec4 tex = texture(albedo_texture, UV);
    ALBEDO = tex.rgb * albedo_color.rgb;
    if (enable_specular) {
        SPECULAR = specular_size;
    } else {
        SPECULAR = 0.0;
    }
}

void light() {
    float ndotl = dot(NORMAL, LIGHT);
    float toon = smoothstep(0.0, band_softness, fract(ndotl * float(toon_steps)) ) ;
    toon = ceil(ndotl * float(toon_steps)) / float(toon_steps);
    toon = clamp(toon, shadow_min, 1.0);

    vec3 result = toon * ALBEDO * LIGHT_COLOR * ATTENUATION;

    if (enable_rim) {
        float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
        result += rim * rim_amount * rim_color.rgb * ATTENUATION;
    }

    DIFFUSE_LIGHT += result;
}