shader_type spatial;
render_mode cull_back, fog_disabled;
// Moose: coarse hollow-haired coat, polished antler, hooves, wet eyes and nose.
// COLOR.rgb is the base colour and COLOR.a says what the surface is (MooseModel:
// 1 fur, 0.6 antler, 0.4 hoof, 0.3 nose, 0.2 eye). UV and UV2.x carry the vertex's
// rest-pose position (z, y and x), so the hair pattern rides with the skin as the
// bones move. `tint` varies the coat from animal to animal.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);

varying vec3 rest;
varying vec3 mnrm;
varying vec3 wpos;
varying float kind;
varying float cloud_v;
varying float spec_v;
varying float dist_v;
varying float body_v;            // 1 on the body, 0 down the legs (no glowing stockings)

void vertex() {
	rest = vec3(UV2.x, UV.y, UV.x);
	mnrm = NORMAL;
	kind = COLOR.a;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_v = atmo_cloud_sun(wpos);
	dist_v = length(wpos - CAMERA_POSITION_WORLD);
	body_v = smoothstep(0.85, 1.1, UV.y);
}

float nz(vec2 p, int ch) {
	vec3 t = texture(noise_tex, p).rgb;
	return ch == 0 ? t.r : (ch == 1 ? t.g : t.b);
}

void fragment() {
	// the palette is written as the colours meant to be seen; lighting works in linear light
	vec3 col = COLOR.rgb * COLOR.rgb;
	float rough = 0.9;
	float spec = 0.15;
	vec3 n = normalize(mnrm);
	vec3 bend = vec3(0.0);
	if (kind > 0.9) {
		col *= tint;
		// hair runs back along the body and down the legs and the bell; the projection
		// follows whichever way the surface faces
		bool leg = rest.y < 0.95 && abs(rest.z + 1.65) > 0.12;
		vec3 w = pow(abs(n), vec3(3.0));
		w /= w.x + w.y + w.z;
		float strand;
		float clump;
		if (leg) {
			strand = nz(vec2((rest.x + rest.z) * 7.0, rest.y * 0.7), 0);
			clump = nz(vec2((rest.x + rest.z) * 2.2, rest.y * 0.25) + 0.4, 1);
		} else {
			float sx = nz(vec2(rest.z * 0.6, rest.y * 8.5 + rest.z * 1.8), 0);
			float sy = nz(vec2(rest.z * 0.5, rest.x * 5.5) + 0.31, 0);
			float sz = nz(vec2(rest.x * 5.5, rest.y * 0.5) + 0.63, 0);
			strand = sx * w.x + sy * w.y + sz * w.z;
			float cx = nz(vec2(rest.z * 0.22, rest.y * 2.1) + 0.2, 1);
			float cy = nz(vec2(rest.z * 0.22, rest.x * 2.1) + 0.5, 1);
			float cz = nz(vec2(rest.x * 2.1, rest.y * 0.22) + 0.8, 1);
			clump = cx * w.x + cy * w.y + cz * w.z;
		}
		// broad, soft patches where the coat lies differently or has faded, a little warmer
		// or greyer from place to place
		float patch = nz(rest.zy * 0.35 + rest.x * 0.2 + 0.13, 2);
		float hue = nz(rest.zy * 0.18 + 0.57, 0);
		col *= (0.8 + 0.4 * strand) * (0.82 + 0.36 * clump) * (0.84 + 0.32 * patch);
		col *= mix(vec3(1.06, 0.98, 0.9), vec3(0.94, 0.98, 1.04), smoothstep(0.35, 0.65, hue));
		// a moose's coat is a dull grey- to blackish-brown, not a saturated red-brown
		col = mix(vec3(dot(col, vec3(0.35, 0.45, 0.2))), col, 0.5) * 1.2;
		// coarse guard hairs tilt the light a little, and on the body broad, soft swellings
		// of muscle and ribs break up the smooth skin
		bend = vec3(0.0, (clump - 0.5) * 0.25, (strand - 0.5) * 0.35);
		if (!leg) {
			float m1 = nz(rest.zy * 0.8 + 0.33, 1);
			float m2 = nz(rest.zy * 1.9 + rest.x * 0.5 + 0.71, 2);
			bend += vec3(0.0, (m1 - 0.5) * 0.3, (m2 - 0.5) * 0.45);
			// a little shade in the hollows under the body and between the legs
			col *= mix(0.88, 1.0, smoothstep(0.9, 1.2, rest.y));
		}
		rough = 0.92;
		spec = 0.14;
	} else if (kind > 0.5) {
		// antler: weathered bone, mottled and finely pitted (sampled on all three planes,
		// so no streaks run across the palm)
		vec3 w3 = pow(abs(n), vec3(3.0));
		w3 /= w3.x + w3.y + w3.z;
		float g = nz(rest.zy * 4.0, 0) * w3.x + nz(rest.xz * 4.0 + 0.3, 0) * w3.y + nz(rest.xy * 4.0 + 0.6, 0) * w3.z;
		float pits = nz(rest.zy * 19.0, 1) * w3.x + nz(rest.xz * 19.0 + 0.3, 1) * w3.y + nz(rest.xy * 19.0 + 0.6, 1) * w3.z;
		col *= (0.8 + 0.34 * g) * (0.84 + 0.26 * pits);
		bend = vec3(pits - 0.5, g - 0.5, pits - g) * 0.8;
		rough = 0.75;
		spec = 0.1;
	} else if (kind > 0.35) {
		rough = 0.45;          // hoof
		spec = 0.35;
	} else if (kind > 0.25) {
		rough = 0.6;           // nostrils: deep and dark, no gloss
		spec = 0.05;
	} else {
		rough = 0.5;           // eye: dark, with a small soft highlight
		spec = 0.18;
	}
	vec3 wn = normalize((MODEL_MATRIX * vec4(normalize(n + bend), 0.0)).xyz);
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	float against = smoothstep(0.35, 0.85, dot(normalize(wpos - CAMERA_POSITION_WORLD), atmo_sun_dir)) * smoothstep(0.42, 0.25, atmo_sun_dir.y);
	col *= 1.0 - 0.45 * against;
	ALBEDO = col * atmo_keep(haze.a);
	ROUGHNESS = rough;
	SPECULAR = spec * (1.0 - haze.a);
	spec_v = SPECULAR;
	vec3 sky_c = mix(atmo_horizon, atmo_top, 0.3);
	vec3 ground_c = vec3(0.4, 0.39, 0.35);
	// light bounced up from the ground into the undersides (the sky's own light the engine adds)
	vec3 fill = ground_c * ground_c * smoothstep(0.1, -0.8, wn.y) * (0.3 + 0.7 * clamp(dot(atmo_sun_col, vec3(0.33)), 0.0, 1.0));
	// and a little of the open sky into the shaded side, so faces in shadow keep their form
	fill += sky_c * sky_c * 0.3 * (0.6 + 0.4 * wn.y) * (0.3 + 0.7 * clamp(dot(atmo_sun_col, vec3(0.33)), 0.0, 1.0));
	EMISSION = atmo_emit(haze, col * fill * 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

void light() {
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	vec3 rad = LIGHT_COLOR * ATTENUATION * cl;
	if (kind > 0.9) {
		// fur: light creeps round into the shade, a soft sheen along the hair, and with
		// the sun behind the animal its outline glows through the long outer hairs
		float ndl = dot(NORMAL, LIGHT);
		float wrap = clamp((ndl + 0.25) / 1.25, 0.0, 1.0);
		float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		// (the glow is light scattered through the hair tips themselves, so it is added as is,
		// not darkened by the coat's colour)
		// (only with the sun really behind, and only close enough for the hair to show: far off
		// the glow would wrap the whole small shape and turn it grey)
		float rim = pow(1.0 - ndv, 9.0) * smoothstep(0.4, 0.9, dot(LIGHT, -VIEW)) * (1.0 - smoothstep(25.0, 45.0, dist_v)) * body_v;
		DIFFUSE_LIGHT += rad * wrap * wrap * 0.95 / PI;
		SPECULAR_LIGHT += LIGHT_COLOR * cl * vec3(1.0, 0.92, 0.8) * rim * 0.45;
		vec3 h = normalize(LIGHT + VIEW);
		// (no sheen: a moose's coarse winter coat is matte)
	} else {
		vec3 dl = vec3(0.0);
		vec3 sl = vec3(0.0);
		atmo_light(NORMAL, LIGHT, VIEW, rad, ROUGHNESS, METALLIC, spec_v, ALBEDO, SPECULAR_AMOUNT, 1, true, dl, sl);
		DIFFUSE_LIGHT += dl;
		SPECULAR_LIGHT += sl;
	}
}
