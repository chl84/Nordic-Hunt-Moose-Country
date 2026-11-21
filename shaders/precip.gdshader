shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, world_vertex_coords;
// Rain or snow falling round the camera (Weather). The mesh is a heap of small quads;
// each quad's colour is its seed: rgb a place in a box, a which share of the full
// strength it belongs to. The box goes with the camera, but every drop keeps its place
// in the world as the camera moves (the box wraps round), falling and drifting
// downwind. Rain: thin streaks along the fall; snow: soft flakes that sway.
#include "res://shaders/atmo.gdshaderinc"

uniform float amount = 0.0;          // 0..1: how many of the drops fall
uniform float snow = 0.0;            // 0 rain, 1 snow
uniform vec3 box = vec3(34.0, 22.0, 34.0);

varying float a_v;
varying vec2 q_uv;

void vertex() {
	vec4 seed = COLOR;
	q_uv = UV;
	a_v = 0.0;
	if (seed.a > amount) {
		VERTEX = vec3(0.0);       // not falling now: a quad of no size draws nothing
	} else {
		float fall = mix(8.5, 1.05, snow) * (0.85 + 0.3 * seed.b);
		vec3 drift = vec3(atmo_wind.x, 0.0, atmo_wind.y) * atmo_wind.w * mix(0.3, 0.75, snow);
		vec3 vel = drift - vec3(0.0, fall, 0.0);
		vec3 p = seed.rgb * box + vel * TIME;
		if (snow > 0.5) {
			p.xz += vec2(sin(TIME * 0.8 + seed.a * 40.0), cos(TIME * 1.1 + seed.r * 30.0)) * 0.35;
		}
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 rel = mod(p - cam + box * 0.5, box) - box * 0.5;
		vec3 centre = cam + rel;
		float d = length(rel);
		// soft at the edges of the box (no popping as drops wrap round) and right at the eye
		vec3 e = abs(rel) / box;
		a_v = (1.0 - smoothstep(0.36, 0.5, max(e.x, max(e.y, e.z)))) * smoothstep(mix(1.0, 0.35, snow), mix(3.5, 1.3, snow), d);
		vec2 c = UV - 0.5;
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		if (snow > 0.5) {
			float s = 0.02 + seed.b * 0.016;
			// further flakes stay at least a pixel or two across, fainter
			float grow = max(1.0, d / 9.0);
			VERTEX = centre + (right * c.x + up * c.y) * s * 2.0 * grow;
			a_v /= grow;
		} else {
			vec3 along = normalize(vel);
			vec3 to_cam = normalize(cam - centre);
			vec3 side = normalize(cross(along, to_cam) + vec3(1e-4));
			float grow = max(1.0, d / 5.0);
			VERTEX = centre + along * c.y * (0.5 + 0.25 * seed.g) + side * c.x * 0.011 * grow;
			a_v /= grow;
		}
	}
}

void fragment() {
	vec2 c = q_uv - 0.5;
	float shape;
	vec3 col;
	// lit by the sky: bright by day, dim at dusk
	float light = clamp(dot(atmo_horizon + atmo_top, vec3(0.2)) + 0.25, 0.3, 1.0);
	if (snow > 0.5) {
		shape = 1.0 - smoothstep(0.18, 0.5, length(c));
		col = vec3(0.93, 0.94, 0.97) * light;
		ALPHA = a_v * shape * 0.9;
	} else {
		shape = (1.0 - smoothstep(0.15, 0.5, abs(c.x))) * smoothstep(0.5, 0.15, abs(c.y));
		col = mix(atmo_horizon, vec3(0.85, 0.87, 0.9), 0.5) * light;
		ALPHA = a_v * shape * 0.3;
	}
	ALBEDO = col;
}
