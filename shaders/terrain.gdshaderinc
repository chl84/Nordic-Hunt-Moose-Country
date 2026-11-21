// Shared by terrain.gdshader (the valley floor) and terrain_far.gdshader (the
// mountains round it): biome colour from a baked map (normal + forest density) and
// several scales of tiling noise. No per-vertex data needed, so mesh LODs match exactly.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_map = true;
#ifndef FAR_RING
// baked at load from where the trees stand (Vegetation): r = under a crown, g = birch
// leaves fallen round it, b = spruce and pine needles; same grid as map_tex
uniform sampler2D litter_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float shadow_reach = 95.0;    // how far the sun's shadow map reaches (m)
#endif

varying vec3 wpos;
varying vec3 vnorm;
varying vec4 vcol;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)
varying float gust_v;               // a gust passing over the grass (see atmo_gust)
varying float spec_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vnorm = NORMAL;
	vcol = COLOR;
	cloud_v = atmo_cloud_sun(wpos);
#ifdef FAR_RING
	gust_v = 0.0;
#else
	gust_v = atmo_gust(noise_tex, wpos.xz, TIME);
#endif
}

// Box mapping: a texture laid on the ground from above where it is flattish and from
// the side (on whichever upright plane the slope faces most) on steep banks and cliffs,
// where a top-down projection would smear into vertical streaks. `side` and `fz` are
// the blend weights; flat ground pays for one lookup, as before. Gradients come in from
// outside so the mip level stays right inside the branches.
vec3 box(sampler2D t, vec3 p, vec3 dx, vec3 dy, float k, vec2 off, float side, float fz) {
	vec3 r = vec3(0.0);
	if (side < 1.0) {
		r += textureGrad(t, p.xz * k + off, dx.xz * k, dy.xz * k).rgb * (1.0 - side);
	}
	if (side > 0.0) {
		vec3 sv = vec3(0.0);
		if (fz < 1.0) {
			sv += textureGrad(t, p.zy * k + off, dx.zy * k, dy.zy * k).rgb * (1.0 - fz);
		}
		if (fz > 0.0) {
			sv += textureGrad(t, p.xy * k + off, dx.xy * k, dy.xy * k).rgb * fz;
		}
		r += sv * side;
	}
	return r;
}

void fragment() {
	vec3 nw;
	float forest;
	vec3 litter = vec3(0.0);
	if (use_map) {
		vec2 muv = ((wpos.xz + 512.0) * 0.5 + 0.5) / 513.0;
		vec4 m = texture(map_tex, muv);
#ifndef FAR_RING
		litter = texture(litter_tex, muv).rgb;
#endif
		vec2 nxz = m.rg * 2.0 - 1.0;
		nw = vec3(nxz.x, sqrt(max(1.0 - dot(nxz, nxz), 0.0)), nxz.y);
		forest = m.b;
	} else {
		nw = normalize(vnorm);
		forest = vcol.b;
	}
	float h = wpos.y;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(25.0, 90.0, dist);
	vec3 wdx = dFdx(wpos);
	vec3 wdy = dFdy(wpos);
#ifdef FAR_RING
	float side = 0.0;     // the far mountains: their own side-on gullies and blotches carry the faces
#else
	float side = smoothstep(0.8, 0.5, nw.y);            // from about 40 degrees, all side-on past 60
#endif
	float face_z = smoothstep(0.35, 0.65, abs(nw.z) / (abs(nw.x) + abs(nw.z) + 0.001));
	vec3 nA = box(noise_tex, wpos, wdx, wdy, 0.011, vec2(0.0), side, face_z);
	vec3 nB = box(noise_tex, wpos, wdx, wdy, 0.083, vec2(0.0), side, face_z);
	vec3 nD = box(detail_tex, wpos, wdx, wdy, 0.097, vec2(0.0), side, face_z);
	// the two finest layers only show within 90 m and 22 m: skip them further out (most of
	// an open view); beyond that the heavily filtered noise would average out to mid-grey anyway
	float close = 1.0 - smoothstep(6.0, 22.0, dist);
	vec3 nC = vec3(0.5);
	vec3 nE = vec3(0.5);
	if (near > 0.0) {
		nC = box(detail_tex, wpos, wdx, wdy, 0.47, vec2(0.0), side, face_z);
		if (close > 0.0) {
			nE = box(detail_tex, wpos, wdx, wdy, 1.83, vec2(0.37), side, face_z);
		}
	}
	float fine = mix(mix(0.5, nD.g, 0.7), nC.r * 0.6 + nD.g * 0.4, near);
	fine = mix(fine, fine * 0.55 + nE.b * 0.45 + (nE.r - 0.5) * 0.25, close);

	// open ground: autumn grass, straw, heather
	vec3 grass = mix(vec3(0.17, 0.215, 0.085), vec3(0.37, 0.315, 0.145), smoothstep(0.3, 0.7, nA.r + (nB.g - 0.5) * 0.5));
	grass = mix(grass, vec3(0.44, 0.39, 0.22), smoothstep(0.55, 0.9, nD.r + (nC.b - 0.5) * 0.5 * near) * 0.45);
	grass = mix(grass, vec3(0.29, 0.125, 0.105), smoothstep(0.6, 0.8, nA.b + (nB.r - 0.5) * 0.35) * 0.7);
	// forest floor: moss and needle litter
	vec3 floor_c = mix(vec3(0.095, 0.145, 0.05), vec3(0.17, 0.12, 0.065), smoothstep(0.35, 0.7, nB.b));
	floor_c = mix(floor_c, vec3(0.15, 0.22, 0.06), smoothstep(0.58, 0.85, nA.g) * 0.6);
	if (!use_map) {
		floor_c = vec3(0.055, 0.085, 0.05);   // distant mountainside forest
	}
	vec3 col = mix(grass, floor_c, smoothstep(0.15, 0.6, forest + (nB.r - 0.5) * 0.3));
	float open_grass = 1.0 - smoothstep(0.15, 0.6, forest + (nB.r - 0.5) * 0.3);
	// what has fallen from the trees: birch leaves gone gold and brown in a ragged ring
	// round each birch, brown needles under spruce and pine
	float leaves = smoothstep(0.12, 0.55, litter.g + (nB.r - 0.5) * 0.35 + (nC.b - 0.5) * 0.35 * near);
	vec3 leaf_c = mix(vec3(0.40, 0.25, 0.07), vec3(0.56, 0.40, 0.10), nD.g);
	col = mix(col, leaf_c * (0.85 + 0.3 * nC.r), leaves * 0.72);
	float needles = smoothstep(0.15, 0.6, litter.b + (nB.g - 0.5) * 0.3);
	col = mix(col, mix(vec3(0.16, 0.10, 0.055), vec3(0.24, 0.16, 0.085), nD.r), needles * 0.4);
	open_grass *= 1.0 - max(leaves, needles);
	// bog margins around the lakes
	float wet = (1.0 - smoothstep(0.7, 2.7, h + (nB.g - 0.5) * 1.2)) * (1.0 - forest);
	vec3 bog = mix(vec3(0.43, 0.31, 0.10), vec3(0.11, 0.09, 0.055), smoothstep(0.55, 0.8, nB.b + (nC.g - 0.5) * 0.3 * near));
	col = mix(col, bog, wet);
	// above the tree line
	float alpine = smoothstep(105.0, 175.0, h + (nA.r - 0.5) * 50.0);
	col = mix(col, mix(vec3(0.33, 0.27, 0.13), vec3(0.23, 0.19, 0.12), nB.r), alpine);
	// rock on steep ground
	float slope = 1.0 - nw.y;
	float rock = smoothstep(0.24, 0.40, slope + (nB.g - 0.5) * 0.16 + alpine * 0.08);
	// mountainside structure big enough to read from a kilometre off: gullies and ribs
	// running down the fall line (noise stretched upright, projected on whichever of the
	// two upright planes the slope faces most), and rock strata in level bands
	float steep = smoothstep(0.1, 0.35, slope);
	// level strata, and blotches on the face at two sizes (~200 m and ~40 m) so it is not
	// all stripes; each taken on both upright planes and blended like the gullies (blending
	// the coordinates instead squeezes the pattern where the slope turns). Every pattern is
	// a plain scaling of the position, so two derivatives of it give all the mip gradients
	// (taken outside the branch, which keeps the mip level right along its edges).
	float gully = 0.5;
	float strata = 0.5;
	vec3 big = vec3(0.5);
	vec3 mid = vec3(0.5);
	if (steep > 0.0) {                                  // flat ground (most of the valley) skips it
		vec2 k_g = vec2(0.011, 0.0021);
		vec2 k_s = vec2(0.0016, 0.011);
		if (face_z < 1.0) {                             // the plane across x: (z, y)
			vec2 p = wpos.zy;
			vec2 dx = wdx.zy;
			vec2 dy = wdy.zy;
			gully = textureGrad(noise_tex, p * k_g + 0.13, dx * k_g, dy * k_g).r;
			strata = textureGrad(noise_tex, p * k_s + 0.4, dx * k_s, dy * k_s).g;
			big = textureGrad(detail_tex, p * 0.0007 + 0.27, dx * 0.0007, dy * 0.0007).rgb;
			mid = textureGrad(noise_tex, p * 0.0034 + 0.71, dx * 0.0034, dy * 0.0034).rgb;
		}
		if (face_z > 0.0) {                             // the plane across z: (x, y)
			vec2 p = wpos.xy;
			vec2 dx = wdx.xy;
			vec2 dy = wdy.xy;
			gully = mix(gully, textureGrad(noise_tex, p * k_g + 0.61, dx * k_g, dy * k_g).r, face_z);
			strata = mix(strata, textureGrad(noise_tex, p * k_s + 0.9, dx * k_s, dy * k_s).g, face_z);
			big = mix(big, textureGrad(detail_tex, p * 0.0007 + 0.52, dx * 0.0007, dy * 0.0007).rgb, face_z);
			mid = mix(mid, textureGrad(noise_tex, p * 0.0034 + 0.18, dx * 0.0034, dy * 0.0034).rgb, face_z);
		}
	}
	// gullies only score some faces deeply; elsewhere they fade to a hint
	float scored = smoothstep(0.38, 0.72, big.r + (mid.g - 0.5) * 0.3);
	gully = mix(0.5, smoothstep(0.25, 0.75, gully), 0.15 + 0.85 * scored);   // 0 down a gully .. 1 along a rib
	float ledge = smoothstep(0.6, 0.68, strata) * steep;
	vec3 rock_c = mix(vec3(0.20, 0.21, 0.22), vec3(0.40, 0.39, 0.37), nB.r) * (0.8 + 0.4 * fine);
	rock_c = mix(rock_c, vec3(0.33, 0.36, 0.23), smoothstep(0.6, 0.8, nA.g) * 0.4);
	// big and middling blotches: lighter and darker, warmer brown and colder blue-grey rock
	vec3 face = rock_c * (0.72 + 0.42 * gully) * (0.92 + 0.14 * smoothstep(0.3, 0.7, strata));
	face *= 0.7 + 0.45 * big.g + 0.55 * (mid.r - 0.5);
	face = mix(face, face * vec3(1.16, 1.02, 0.86), smoothstep(0.45, 0.8, big.b) * 0.7);
	face = mix(face, face * vec3(0.82, 0.88, 1.0), smoothstep(0.5, 0.8, mid.b) * 0.5);
	rock_c = mix(rock_c, face, steep);
	// ledges catch grass and lichen low down
	rock_c = mix(rock_c, vec3(0.29, 0.27, 0.15), ledge * (1.0 - smoothstep(150.0, 260.0, h)) * 0.7);
	col = mix(col, rock_c, rock);
	// shoreline and lake bed
	float shore = 1.0 - smoothstep(0.05, 0.8, h + (nB.r - 0.5) * 0.5);
	col = mix(col, mix(vec3(0.35, 0.31, 0.23), vec3(0.24, 0.22, 0.18), nC.b), shore);
	col = mix(col, vec3(0.09, 0.10, 0.07), smoothstep(-0.2, -2.5, h));
	// first snow on the peaks
	// (it lingers lower down the gullies and on the ledges, so the snowline breaks into tongues)
	// (a snowy day brings the snowline down the mountainsides)
	float snow = smoothstep(285.0, 345.0, h + atmo_weather.y * 190.0 + (nA.b - 0.5) * 70.0 - slope * 90.0 + ((0.5 - gully) * 90.0 + ledge * 40.0 + (mid.g - 0.5) * 80.0 + (big.r - 0.5) * 60.0) * steep);
	col = mix(col, vec3(0.90, 0.92, 0.96), snow);
	col *= mix(1.0, 0.62 + 0.76 * fine, 1.0 - snow * 0.7);
	// the day's weather (atmo_weather): the first snow lying on all but the steepest
	// ground, patchy where it is thin and thinner under the crowns; in the rain the
	// ground darkens and takes a sheen
	float fresh = 0.0;
	if (atmo_weather.y > 0.0) {
		float lie = atmo_weather.y * 0.92 + (nB.r - 0.5) * 0.7 + (nA.g - 0.5) * 0.5 + (nC.g - 0.5) * 0.35 * near + (nE.b - 0.5) * 0.3 * close;
		fresh = smoothstep(0.45, 0.68, lie) * (1.0 - smoothstep(0.3, 0.5, slope)) * (1.0 - shore) * (1.0 - litter.r * 0.8) * (1.0 - forest * 0.25);
		// (a little blue in its hollows, a sparkle of crystals close up)
		vec3 snow_c = mix(vec3(0.66, 0.7, 0.78), vec3(0.8, 0.81, 0.84), smoothstep(0.3, 0.7, nB.g + (nD.r - 0.5) * 0.5));
		col = mix(col, snow_c * (0.94 + 0.1 * fine), fresh);
	}
	float soaked = atmo_weather.x * (1.0 - max(snow, fresh));
	col *= 1.0 - 0.3 * soaked;
#ifdef FAR_RING
	// trees shade the ground beyond shadow-map range
	col *= 1.0 - forest * 0.22 * smoothstep(60.0, 160.0, dist);
#else
	// under a crown less of the sky reaches the ground, and beyond the shadow map's reach
	// the trees' own shadows have to be stood in for, tree by tree
	col *= 1.0 - litter.r * 0.12;
	col *= 1.0 - max(forest * 0.1, litter.r * 0.38) * smoothstep(shadow_reach * 0.7, shadow_reach, dist);
	// gusts run on across the open meadow beyond the grass blades, as a faint sheen
	col *= 1.0 + gust_v * 0.1 * open_grass * (1.0 - rock) * (1.0 - wet) * (1.0 - max(snow, fresh)) * (1.0 - shore)
			* smoothstep(12.0, 35.0, dist) * (1.0 - smoothstep(150.0, 230.0, dist));
#endif

	nw.xz += (nE.rg - 0.5) * 0.5 * close * (1.0 - snow) * (1.0 - 0.8 * fresh);
	nw.xz += (nC.gb - 0.5) * 0.7 * near * (1.0 - snow) * (1.0 - 0.6 * fresh);
	// fresh snow lies in soft drifts and lumps over what is under it
	nw.xz += ((nB.gb - 0.5) * 0.45 + (nD.gr - 0.5) * 0.25) * fresh;
	nw.xz += (nD.rb - 0.5) * 0.25 * (1.0 - snow);
	nw.xz += (nB.rg - 0.5) * 0.12;
	// ribs and gullies turn a little across the fall line, so the low sun picks them out
	vec3 across = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
	nw += across * (gully - 0.5) * 0.6 * steep * rock * (1.0 - snow * 0.5);
	// lumps and hollows from the blotches, tilting both across and down the slope
	vec3 down = normalize(vec3(nw.x, 0.0, nw.z) + vec3(0.0001));
	nw += (across * (mid.g - 0.5) + down * (mid.b - 0.5) * 0.8 + across * (big.g - 0.5) * 0.6) * 0.7 * steep * (1.0 - snow * 0.4);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nw), 0.0)).xyz);
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = col * atmo_keep(haze.a);
	ROUGHNESS = mix(mix(0.95, 0.55, max(shore * 0.7, wet * 0.4)), 0.45, soaked * 0.6);
	SPECULAR = (0.15 + 0.12 * soaked) * (1.0 - haze.a);
	spec_v = SPECULAR;
	EMISSION = atmo_emit(haze, vec3(0.0));
}

// the engine's own lighting (Burley and Schlick-GGX; plain Lambert for the far mountains),
// with the clouds taking their share of the sun
void light() {
	vec3 dl = vec3(0.0);
	vec3 sl = vec3(0.0);
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
#ifdef FAR_RING
	atmo_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR * ATTENUATION * cl, ROUGHNESS, METALLIC, 0.0, ALBEDO, SPECULAR_AMOUNT, 0, false, dl, sl);
#else
	atmo_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR * ATTENUATION * cl, ROUGHNESS, METALLIC, spec_v, ALBEDO, SPECULAR_AMOUNT, 1, true, dl, sl);
#endif
	DIFFUSE_LIGHT += dl;
	SPECULAR_LIGHT += sl;
}
