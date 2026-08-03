shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform float effect_decay : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool is_particle = true;

group_uniforms Color;
uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;
uniform vec3 tertiary_color : source_color;
uniform float emission = 2.0;

group_uniforms Noise;
uniform sampler2D smoke_texture;
uniform vec2 noise_scale = vec2(1.0);
uniform vec2 extra_scale = vec2(1.0);
uniform vec2 noise_scroll = vec2(0.0, 0.2);

// Kept for material/scene compatibility with the asset pack.
group_uniforms Shading;
uniform bool use_stepped_shading = true;
uniform float shadow_steps : hint_range(2.0, 12.0, 0.01) = 3.0;

group_uniforms Displacement;
uniform float displacement_amount = 0.2;
uniform float pole_displacement_amount = 0.0;

group_uniforms Normal;
uniform sampler2D normal_texture;

void fragment() {
	float decay = is_particle ? (1.0 - COLOR.a * (1.0 - effect_decay)) : effect_decay;

	vec2 noise_uv = (UV + COLOR.r + noise_scroll * TIME) * noise_scale * extra_scale;
	float noise = texture(smoke_texture, noise_uv).r;

	float noise_decay = clamp(decay * 2.0, 0.0, 1.0);
	float noise_value = max(1.0 - noise - noise_decay, 0.0);
	noise_value = smoothstep(0.0, 0.5, noise_value);

	vec3 color = mix(tertiary_color, primary_color, noise_value);

	ALBEDO = color;
	EMISSION = color * noise_value * emission;

	float alpha_decay = min(decay, 1.0);
	ALPHA = clamp((1.0 + noise) - (alpha_decay * 2.0), 0.0, 1.0);
}
