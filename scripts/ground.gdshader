shader_type spatial;
render_mode cull_back;
uniform sampler2D ground_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 earth_tint : source_color = vec4(.64,.53,.36,1.);
uniform float texture_scale = .22;
uniform float detail_strength = .28;
varying vec3 world_position;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float smooth_noise(vec2 p) {
 vec2 i=floor(p), f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz; }
void fragment() {
 vec2 uv=world_position.xz*texture_scale;
 vec3 scan=texture(ground_color,uv).rgb;
 float variation=.91+.16*smooth_noise(world_position.xz*.026);
 ALBEDO=mix(earth_tint.rgb,earth_tint.rgb*scan*1.7,detail_strength)*variation;
 ROUGHNESS=.94;
 vec3 detail=texture(ground_normal,uv).rgb*2.-1.;
 vec3 normal_world=normalize(vec3(-detail.x*.16,1.,-detail.y*.16));
 NORMAL=normalize((VIEW_MATRIX*vec4(normal_world,0.)).xyz);
}
