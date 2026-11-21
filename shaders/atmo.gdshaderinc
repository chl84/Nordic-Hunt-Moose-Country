// Shared atmosphere: the sky gradient, and the haze that fades the landscape
// into exactly that sky. Values are set by SkySystem as global uniforms
// (declared in project.godot), all in linear colour.

global uniform vec3 atmo_sun_dir;   // unit vector towards the sun
global uniform vec3 atmo_sun_col;   // sun colour x energy
global uniform vec3 atmo_top;       // sky at the zenith
global uniform vec3 atmo_horizon;   // sky at the horizon
global uniform vec4 atmo_haze;      // rgb = haze colour, a = strength of the haze band low in the sky
global uniform vec4 atmo_fog;       // x = haze density at lake level (1/m), y = scale height (m), z = sun glow
global uniform vec4 atmo_cloud;     // xy = drift of the cloud shadows, z = share of the sun a cloud takes, w = sun let through over the camera
global uniform sampler2D atmo_cloud_tex : filter_linear, repeat_enable;

// Sky colour without clouds or the sun disc.
vec3 atmo_sky(vec3 dir) {
	float y = max(dir.y, 0.0);
	float t = pow(y, 0.45);
	vec3 col = mix(atmo_horizon, atmo_top, t);
	float sd = max(dot(dir, atmo_sun_dir), 0.0);
	col += atmo_sun_col * (pow(sd, 6.0) * atmo_fog.z * (1.0 - t * 0.75));
	col = mix(col, atmo_haze.rgb, atmo_haze.a * (1.0 - smoothstep(0.0, 0.45, y)));
	return col;
}

// The renderer reads ALBEDO and EMISSION as sRGB-encoded values and blends its own
// fog in linear light. To fade a surface by `a` exactly as that fog would (so the
// landscape and plain-material things like the moose and the cabin agree):
//   ALBEDO *= atmo_keep(a);   EMISSION = atmo_emit(haze, extra);
// (square and square root stand in for the sRGB curve: close enough, and far cheaper per pixel)
float atmo_keep(float a) {
	return sqrt(1.0 - a);
}

// `extra_lin` is any light the surface gives off itself, in linear units.
vec3 atmo_emit(vec4 haze, vec3 extra_lin) {
	return sqrt(extra_lin * (1.0 - haze.a) + haze.rgb * haze.rgb * haze.a);
}

// rgb = the colour distance fades to, a = how much of it. The haze thins with
// altitude, so peaks stand clear of the mist that fills the valley.
vec4 atmo_fogging(vec3 wpos, vec3 cam) {
	vec3 v = wpos - cam;
	float dist = length(v);
	vec3 dir = v / max(dist, 0.001);
	float k = clamp(v.y / atmo_fog.y, -3.0, 30.0);
	float avg = abs(k) < 0.01 ? 1.0 : (1.0 - exp(-k)) / k;
	avg *= exp(-max(cam.y, 0.0) / atmo_fog.y);
	float amount = 1.0 - exp(-atmo_fog.x * dist * avg);
	return vec4(atmo_sky(dir), amount);
}

// Sunlight let through the clouds at world point `p`, relative to what reaches the
// camera. The sun's own energy is already scaled by the clouds over the camera, so
// plain materials (the moose, the rifle) are right where they matter; shaders that call
// this correct it everywhere else. SkySystem.cloud_sun_at() does the same sums on the CPU.
float atmo_cloud_sun(vec3 p) {
	vec3 s = atmo_sun_dir;
	vec2 q = p.xz + s.xz / max(s.y, 0.2) * (400.0 - p.y);     // up the sun's ray to the cloud deck
	// (fract: a global texture is sampled without wrapping, whatever its hint says)
	float c = textureLod(atmo_cloud_tex, fract(q * 0.0009 + atmo_cloud.xy), 0.0).r * 0.65
			+ textureLod(atmo_cloud_tex, fract(q * 0.0026 + atmo_cloud.xy * 1.7 + 0.31), 0.0).g * 0.35;
	return (1.0 - smoothstep(0.54, 0.6, c) * atmo_cloud.z) / max(atmo_cloud.w, 0.05);
}

// Gusts: broad bands of stronger wind rolling downwind across the valley (0..1).
// The grass and the open ground take them from the same texture, so the waves run on
// from the blades into the meadow beyond them.
float atmo_gust(sampler2D t, vec2 xz, float time) {
	vec2 wd = vec2(0.8, 0.6);
	vec2 uv = vec2(dot(xz, wd) * 0.014 - time * 0.1, dot(xz, vec2(-wd.y, wd.x)) * 0.006);
	return smoothstep(0.45, 0.78, textureLod(t, uv, 0.0).r);
}

float atmo_schlick(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

// Godot's own lighting for one light - its Lambert (mode 0), Burley (1) or wrapped
// Lambert (2) diffuse and Schlick-GGX specular - for shaders that write light() only
// so the clouds can dim the sun. `radiance` is LIGHT_COLOR * ATTENUATION (* clouds).
void atmo_light(vec3 N, vec3 L, vec3 V, vec3 radiance, float rough, float metal, float spec,
		vec3 albedo, float spec_amount, int mode, bool with_spec, inout vec3 dl, inout vec3 sl) {
	float NdotL = dot(N, L);
	float cNdotL = max(NdotL, 0.0);
	float cNdotV = max(dot(N, V), 1e-4);
	vec3 H = normalize(V + L);
	float cLdotH = clamp(dot(L, H), 0.0, 1.0);
	if (metal < 1.0) {
		float d;
		if (mode == 2) {
			d = max(0.0, (NdotL + rough) / ((1.0 + rough) * (1.0 + rough))) * (1.0 / PI);
		} else if (mode == 1) {
			float fd90 = 2.0 * cLdotH * cLdotH * rough - 0.5;
			d = (1.0 / PI) * (1.0 + fd90 * atmo_schlick(cNdotV)) * (1.0 + fd90 * atmo_schlick(cNdotL)) * cNdotL;
		} else {
			d = cNdotL * (1.0 / PI);
		}
		dl += radiance * d;
	}
	if (with_spec && rough > 0.0) {
		float cNdotH = clamp(dot(N, H), 0.0, 1.0);
		float a = rough * rough;
		float am = cNdotH * a;
		float k = a / (1.0 - cNdotH * cNdotH + am * am);
		float D = k * k * (1.0 / PI);
		float G = 0.5 / mix(2.0 * cNdotL * cNdotV, cNdotL + cNdotV, a);
		vec3 f0 = mix(vec3(0.16 * spec * spec), albedo, metal);
		float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), metal, 1.0);
		vec3 F = f0 + (f90 - f0) * atmo_schlick(cLdotH);
		sl += cNdotL * D * F * G * radiance * spec_amount;
	}
}
