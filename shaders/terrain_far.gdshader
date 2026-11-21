shader_type spatial;
render_mode cull_back, diffuse_lambert, fog_disabled, shadows_disabled, specular_disabled;
// The mountains round the valley (480 m and more away): the same ground, without the
// lookups that cannot show from there - shadow maps reach 160 m at most, and the
// faint sheen would be lost in the haze anyway. Set use_map = false on its material.
#define FAR_RING
#include "res://shaders/terrain.gdshaderinc"
