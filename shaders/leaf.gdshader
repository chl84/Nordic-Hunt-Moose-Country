shader_type spatial;
render_mode cull_disabled, fog_disabled;
// A falling birch leaf: a pointed oval with a pale midrib, cut out of a small quad
// (UV y = 0 at the tip). Instance colour is its autumn colour. Lit from both sides,
// glowing a little with the sun behind it, and shaded by the clouds like the trees.
#include "res://shaders/atmo.gdshaderinc"

varying vec3 wpos;
varying float cloud_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_v = atmo_cloud_sun(wpos);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;                       // -1..1, tip at y = -1, stalk at +1
	float along = p.y * 0.5 + 0.5;                 // 0 at the tip .. 1 at the base
	float w = 0.86 * sqrt(max(0.0, 1.0 - p.y * p.y)) * mix(0.55, 1.0, smoothstep(0.0, 0.7, along));
	float stalk = step(abs(p.x), 0.05) * step(0.85, along);
	if (abs(p.x) > w && stalk < 0.5) {
		discard;
	}
	float rib = 1.0 - smoothstep(0.0, 0.07, abs(p.x));
	vec3 col = COLOR.rgb * (0.82 + 0.25 * (1.0 - abs(p.x) / max(w, 0.01))) * (1.0 + rib * 0.18);
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = col * atmo_keep(haze.a);
	ROUGHNESS = 0.75;
	SPECULAR = 0.2 * (1.0 - haze.a);
	EMISSION = atmo_emit(haze, vec3(0.0));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * 0.6;
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cl * (abs(ndl) * 0.85 + 0.1 + through) / PI;
}
