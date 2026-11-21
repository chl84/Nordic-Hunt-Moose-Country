shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, fog_disabled, ambient_light_disabled;
// Lake water. Depth comes from a baked height texture (no depth-buffer read)
// and the mirror image is worked out, not rendered: the sky from the shared
// atmosphere, the mountains from a baked skyline. Only the sun's glitter is
// left to the engine, which keeps it cheap on integrated graphics.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D skyline_tex : filter_linear, repeat_enable;   // how high the land stands, by compass direction
uniform vec3 deep_color : source_color = vec3(0.03, 0.085, 0.105);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.17, 0.14);
uniform float ripple = 1.0;
// the trees round the shores: forest density (b) on the terrain map, and the litter map
// baked from the trees themselves (g = birch leaves, b = spruce and pine needles)
uniform sampler2D map_tex : filter_linear, repeat_disable;
uniform sampler2D litter_tex : filter_linear, repeat_disable, hint_default_black;
uniform bool shore_trees = true;

varying vec3 wpos;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)
varying float spec_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float forest_at(vec2 q) {
	vec2 uv = ((q + 512.0) * 0.5 + 0.5) / 513.0;
	return textureLod(map_tex, uv, 0.0).b;
}

// The far shore mirrored from water point `p` in direction `r`: walks out across the
// forest map along the reflected ray to where the trees begin, and checks the ray
// against their tops there. rgb = colour, a = how much of the mirror it fills.
vec4 shore(vec3 p, vec3 r, float rough) {
	vec2 dir = normalize(r.xz + vec2(0.00001));
	float tan_r = r.y / max(length(r.xz), 0.0001);
	float d = 2.0;
	float prev = 0.0;
	float hit = -1.0;
	for (int i = 0; i < 22; i++) {
		if (d * tan_r > 17.0 || d > 650.0) {
			break;                                     // above every treetop, or out of range
		}
		if (forest_at(p.xz + dir * d) > 0.35) {
			hit = d;
			break;
		}
		prev = d;
		d = d * 1.3 + 1.5;
	}
	if (hit < 0.0) {
		return vec4(0.0);
	}
	// home in on the forest's edge
	for (int k = 0; k < 3; k++) {
		float m = (prev + hit) * 0.5;
		if (forest_at(p.xz + dir * m) > 0.35) {
			hit = m;
		} else {
			prev = m;
		}
	}
	vec2 q = p.xz + dir * (hit + 5.0);                  // a few metres in among the trees
	float f = forest_at(q);
	// ragged tops: spruce spires and rounder birch crowns, gaps where the forest thins
	float rag = textureLod(noise_tex, q * 0.09, 0.0).r * 0.65 + textureLod(noise_tex, q * 0.37, 0.0).g * 0.35;
	float top = (2.0 + 11.0 * smoothstep(0.35, 0.8, f)) * (0.6 + 0.8 * rag);
	float y = hit * tan_r;                              // where the ray passes over the forest's edge
	float soft = 0.5 + hit * (0.004 + rough * 0.012);
	float cover = smoothstep(top + soft, top - soft, y);
	// what grows there: gold birch, dark spruce and pine
	vec3 lit = textureLod(litter_tex, ((q + 512.0) * 0.5 + 0.5) / 513.0, 0.0).rgb;
	float birch = smoothstep(0.1, 0.7, lit.g / (lit.g + lit.b + 0.08));
	vec3 light = 0.3 + atmo_sun_col * 0.7;
	vec3 col = mix(vec3(0.04, 0.065, 0.048), vec3(0.42, 0.31, 0.08), birch) * light;
	col *= 0.75 + 0.5 * rag;
	// the strip of yellowed grass and bog along the shore, under the trees
	col = mix(col, vec3(0.30, 0.25, 0.11) * light, smoothstep(1.3, 0.5, y));
	// haze over the water between here and there
	float hz = 1.0 - exp(-atmo_fog.x * hit);
	col = mix(col, atmo_sky(vec3(r.x, 0.03, r.z)), hz);
	return vec4(col, cover);
}

// What the water mirrors in world direction `r` (pointing up and away) from `p`.
vec3 mirror(vec3 p, vec3 r, float rough) {
	vec3 sky = atmo_sky(r);
	float land = texture(skyline_tex, vec2(atan(r.x, r.z) / TAU + 0.5, 0.5)).r * 0.6;
	// distant slopes: lit where they face the sun, blue in their own shade, snow on top, all behind the valley haze
	vec2 flat_dir = normalize(r.xz + vec2(0.0001));
	float facing = 0.5 - 0.5 * dot(flat_dir, normalize(atmo_sun_dir.xz + vec2(0.0001)));
	vec3 slope_c = mix(vec3(0.085, 0.10, 0.13), vec3(0.30, 0.29, 0.27) * (0.35 + atmo_sun_col), facing);
	float snow = smoothstep(0.62, 0.86, r.y / max(land, 0.02)) * smoothstep(0.16, 0.26, land);
	slope_c = mix(slope_c, vec3(0.62, 0.66, 0.72) * (0.4 + 0.6 * atmo_sun_col), snow);
	float far_haze = 1.0 - exp(-atmo_fog.x * 900.0 * mix(1.0, 0.45, clamp(r.y / 0.3, 0.0, 1.0)));
	slope_c = mix(slope_c, atmo_sky(vec3(r.x, 0.03, r.z)), far_haze);
	vec3 col = mix(sky, slope_c, smoothstep(land + 0.012 + rough * 0.03, land - 0.012, r.y));
	// the trees along the far shore
	if (shore_trees) {
		vec4 sh = shore(p, r, rough);
		col = mix(col, sh.rgb, sh.a * 0.92);
	}
	return col;
}

void fragment() {
	vec2 muv = ((wpos.xz + 512.0) * 0.5 + 0.5) / 513.0;
	float depth = texture(depth_tex, muv).r * 8.0;
	vec3 to_frag = wpos - CAMERA_POSITION_WORLD;
	float dist = length(to_frag);
	vec3 view_w = to_frag / max(dist, 0.001);
	// three sizes of ripple drifting across each other; the finest only shows up close
	vec3 a = texture(noise_tex, wpos.xz * 0.071 + TIME * vec2(0.013, 0.008)).rgb;
	vec3 b = texture(noise_tex, wpos.xz * 0.23 + TIME * vec2(-0.021, 0.015)).rgb;
	vec3 c = texture(noise_tex, wpos.xz * 0.74 + TIME * vec2(0.03, -0.037)).rgb;
	vec2 g = (a.rg - 0.5) * 0.7 + (b.gb - 0.5) * 0.55 + (c.rb - 0.5) * 0.45 * (1.0 - smoothstep(8.0, 60.0, dist));
	g *= ripple * mix(1.0, 0.22, smoothstep(30.0, 260.0, dist));
	vec3 nw = normalize(vec3(g.x * 0.26, 1.0, g.y * 0.26));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float ndv = clamp(dot(-view_w, nw), 0.0, 1.0);
	float fres = 0.05 + 0.95 * pow(1.0 - ndv, 4.5);
	// the mirror image is taken off a calmer surface than the glitter, or the far shore
	// would dissolve into noise; ripples mostly stretch it up and down
	float calm = mix(0.5, 0.1, smoothstep(10.0, 180.0, dist));
	vec3 nm = normalize(vec3(g.x * 0.26 * calm, 1.0, g.y * 0.26 * calm));
	vec3 r = reflect(view_w, nm);
	r.y = abs(r.y) + 0.002 + abs(g.y) * 0.02;
	vec3 refl = mirror(wpos, normalize(r), length(g));

	// the water itself: clear over the shallows, dark and green-blue over the deeps
	vec3 body = mix(shallow_color, deep_color, smoothstep(0.0, 3.2, depth));
	float foam = (1.0 - smoothstep(0.0, 0.2, depth)) * smoothstep(0.4, 0.72, b.r + sin(TIME * 0.9 + wpos.x * 0.35 + wpos.z * 0.2) * 0.12);
	body = mix(body, vec3(0.72, 0.78, 0.78), foam * 0.45);
	vec3 skylight = atmo_horizon * 0.55 + atmo_top * 0.55;

	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = body * (1.0 - fres) * atmo_keep(haze.a);
	vec3 surface = body * skylight * (1.0 - fres) + refl * fres;
	EMISSION = atmo_emit(haze, surface * surface);
	ALPHA = clamp(mix(smoothstep(0.0, 1.5, depth) * 0.84 + 0.1, 1.0, fres), 0.0, 1.0) * smoothstep(0.0, 0.05, depth);
	ROUGHNESS = mix(0.05, 0.2, smoothstep(40.0, 300.0, dist));
	SPECULAR = 0.75 * (1.0 - haze.a);
	spec_v = SPECULAR;
	cloud_v = atmo_cloud_sun(wpos);     // (per pixel: the water plane's vertices are 120 m apart)
}

// the engine's own Burley and Schlick-GGX lighting, with the clouds taking their share of the sun
void light() {
	vec3 dl = vec3(0.0);
	vec3 sl = vec3(0.0);
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	atmo_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR * ATTENUATION * cl, ROUGHNESS, METALLIC, spec_v, ALBEDO, SPECULAR_AMOUNT, 1, true, dl, sl);
	DIFFUSE_LIGHT += dl;
	SPECULAR_LIGHT += sl;
}
