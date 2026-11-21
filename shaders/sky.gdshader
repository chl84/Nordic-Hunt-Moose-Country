shader_type sky;
// Gradient sky with a sun, horizon haze and a drifting, sun-lit cloud layer.
// The gradient itself lives in atmo.gdshaderinc so the landscape can fade into it.
#include "res://shaders/atmo.gdshaderinc"

uniform vec3 ground_color : source_color = vec3(0.2, 0.22, 0.2);
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_cover = 0.45;
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_dark : source_color = vec3(0.5, 0.55, 0.62);

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 col = atmo_sky(dir);
	float sd = max(dot(dir, atmo_sun_dir), 0.0);
	if (y > -0.02) {
		vec2 cuv = dir.xz / (y + 0.17);
		float c = texture(cloud_tex, cuv * 0.045 + cloud_offset).r * 0.56
				+ texture(cloud_tex, cuv * 0.12 + cloud_offset * 1.7).g * 0.30
				+ texture(cloud_tex, cuv * 0.37 + cloud_offset * 2.6).b * 0.14;
		float cov = smoothstep(1.0 - cloud_cover - 0.14, 1.0 - cloud_cover + 0.22, c);
		cov *= smoothstep(-0.02, 0.1, y);
		// thick middles are shaded, thin edges catch the light
		float thick = smoothstep(0.45, 0.95, c);
		vec3 ccol = mix(cloud_lit, cloud_dark, thick * 0.75);
		ccol += atmo_sun_col * (pow(sd, 3.0) * 0.38 + pow(sd, 24.0) * (1.0 - thick) * 0.9);
		// distance: clouds low in the sky sink into the haze
		float low = 1.0 - smoothstep(0.0, 0.34, y);
		ccol = mix(ccol, mix(atmo_horizon, atmo_haze.rgb, atmo_haze.a), low * 0.75);
		col = mix(col, ccol, cov * 0.9);
	}
	col += atmo_sun_col * (smoothstep(0.99935, 0.99975, sd) * 5.0 + pow(sd, 350.0) * 1.2);
	col = mix(col, ground_color, smoothstep(0.0, -0.1, y));
	COLOR = col;
}
