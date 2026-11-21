shader_type spatial;
render_mode cull_back, fog_disabled, world_vertex_coords;
// Trees, bushes and rocks: vertex colour is the albedo (multiplied by the
// MultiMesh instance colour), vertex alpha is how much the wind may move it -
// which also marks leaves and needles (thin, light shines through) apart from
// trunks and stone.
#include "res://shaders/atmo.gdshaderinc"

uniform float wind_strength = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.92;
uniform float birch_bark = 0.0;     // 1 = draw birch bark on the pale parts (uses the trunk's texture coordinates)
uniform float bark_kind = 0.0;      // 2 = spruce bark, 3 = pine bark on the wood (UV.x round the stem, height in the tree)
uniform float fine_range = 32.0;    // limbs and dead twigs (UV.y >= 500; trunks use UV.y for metres up the stem) are drawn only this close

varying float sway;
varying vec3 wpos;
varying float hgt;                  // metres up the tree
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)

// (world_vertex_coords: VERTEX and NORMAL arrive in world space, so the wind is
// simply added; no per-vertex matrix inverse to take it back into the model)
void vertex() {
	sway = COLOR.a;
	vec3 wp = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float my = (wp.y - origin.y) / max(length(MODEL_MATRIX[1].xyz), 0.001);   // height in the model
	hgt = my;
	float phase = origin.x * 0.31 + origin.z * 0.27;
	float gust = sin(TIME * 0.9 + phase) * 0.6 + sin(TIME * 2.3 + phase * 1.7 + wp.y * 0.4) * 0.4;
	float flutter = sin(TIME * 5.1 + wp.x * 2.1 + wp.z * 1.7) * 0.25;
	vec3 offs = vec3(0.8, 0.0, 0.6) * (gust + flutter * sway) * 0.07 * sway * wind_strength * (0.4 + my * 0.09);
	VERTEX = wp + offs;
	wpos = VERTEX;
	cloud_v = atmo_cloud_sun(origin);
	// further out they are thinner than a pixel, and thin triangles are costly to draw:
	// fold them away to nothing
	if (UV.y >= 500.0 && length(origin - CAMERA_POSITION_WORLD) > fine_range) {
		VERTEX = origin;
	}
}

void fragment() {
	// a gentle curve: deep enough for forest shade, without crushing bark and needles to black
	vec3 alb = pow(COLOR.rgb, vec3(1.3)) * 0.62;
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, 0.88);
	if (birch_bark > 0.5) {
		// only the white stem, not the dark twigs. UV: once round the trunk, metres up it
		float pale = smoothstep(0.4, 0.65, dot(COLOR.rgb, vec3(0.333)));
		// thin dark streaks running round the stem, a few longer ones among them
		float fine = smoothstep(0.6, 0.68, texture(noise_tex, vec2(UV.x * 3.0 + 0.37, UV.y * 14.0)).g);
		float wide = smoothstep(0.66, 0.72, texture(noise_tex, vec2(UV.x * 2.0, UV.y * 6.0)).r);
		// rough black bark creeping up from the foot, split by pale cracks, and the odd dark scar higher up
		float creep = texture(noise_tex, vec2(UV.x, UV.y * 0.7)).b;
		float foot = smoothstep(1.5, 0.15, UV.y + (creep - 0.5) * 1.8) * smoothstep(0.38, 0.52, texture(noise_tex, vec2(UV.x * 2.0, UV.y * 1.9)).g);
		float scar = smoothstep(0.73, 0.78, texture(noise_tex, vec2(UV.x + 0.6, UV.y * 0.9)).r);
		float dark = clamp(max(max(fine * 0.8, wide * 0.7), max(foot, scar)), 0.0, 1.0) * pale;
		alb = mix(alb, vec3(0.04, 0.036, 0.034), dark * 0.93);
	}
	if (bark_kind > 1.5) {
		// only the wood: needles and leaves sway more than any trunk or limb
		float wood = 1.0 - smoothstep(0.55, 0.7, sway);
		if (bark_kind < 2.5) {
			// spruce: thin grey-brown bark of small round scales, the odd resin streak,
			// and grey-green lichen on the lower stem
			float sc = texture(noise_tex, vec2(UV.x * 9.0, hgt * 2.6)).r;
			float sc2 = texture(noise_tex, vec2(UV.x * 23.0 + 0.4, hgt * 7.0)).g;
			vec3 b = alb * (0.72 + 0.46 * sc) * (0.84 + 0.32 * sc2);
			b = mix(b, b * vec3(0.72, 0.62, 0.55), smoothstep(0.66, 0.72, sc2) * 0.6);
			float lic = smoothstep(0.64, 0.7, texture(noise_tex, vec2(UV.x * 2.0 + 0.2, hgt * 0.7)).b) * smoothstep(0.45, 0.6, sc2) * (1.0 - smoothstep(0.8, 3.5, hgt));
			b = mix(b, vec3(0.22, 0.235, 0.20), lic * 0.55);
			float resin = smoothstep(0.75, 0.78, texture(noise_tex, vec2(UV.x * 3.0 + 0.7, hgt * 0.25)).r);
			b = mix(b, vec3(0.30, 0.20, 0.09), resin * 0.45);
			alb = mix(alb, b, wood);
		} else {
			// pine: thick plates split by deep furrows low down, giving way to thin, flaking,
			// orange bark higher up (the vertex colour already carries that change of colour)
			float n1 = texture(noise_tex, vec2(UV.x * 2.4, hgt * 0.16)).r;
			float n2 = texture(noise_tex, vec2(UV.x * 4.5 + 0.3, hgt * 0.75)).g;
			// raised plates (light, a little red-grey) between dark furrows that wander up the stem
			float furrow = 1.0 - smoothstep(0.03, 0.09, abs(n1 - 0.5) + (n2 - 0.5) * 0.06);
			float split = 1.0 - smoothstep(0.02, 0.05, abs(n2 - 0.5));
			vec3 thick = alb * vec3(1.32, 1.24, 1.2) * (0.85 + 0.3 * texture(noise_tex, vec2(UV.x * 3.0 + 0.5, hgt * 0.6)).b);
			thick = mix(thick, thick * vec3(1.15, 0.95, 0.85), smoothstep(0.55, 0.75, n2) * 0.45);
			thick *= 1.0 - max(furrow * 0.75, split * 0.3);
			float f1 = texture(noise_tex, vec2(UV.x * 8.0 + 0.1, hgt * 2.2)).b;
			float f2 = texture(noise_tex, vec2(UV.x * 18.0, hgt * 5.0)).r;
			vec3 thin = alb * (0.86 + 0.24 * f2);
			thin = mix(thin, thin * vec3(1.25, 1.17, 0.95), smoothstep(0.6, 0.65, f1) * 0.8);   // fresh paper-thin flakes
			thin *= 1.0 - (1.0 - smoothstep(0.02, 0.05, abs(f1 - 0.45))) * 0.45;               // their curled edges
			float low = 1.0 - smoothstep(3.0, 6.0, hgt + (n2 - 0.5) * 2.5);
			alb = mix(alb, mix(thin, thick, low), wood);
		}
	}
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = alb * atmo_keep(haze.a);
	ROUGHNESS = roughness;
	SPECULAR = 0.12 * (1.0 - haze.a);
	EMISSION = atmo_emit(haze, vec3(0.0));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// light wraps round a soft crown, and thin foliage glows when the sun is behind it
	float wrap = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
	float leaf = smoothstep(0.15, 0.6, sway);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * clamp(0.6 - ndl * 0.5, 0.0, 1.0) * leaf * 0.7;
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cl * (wrap + through) / PI;
}
