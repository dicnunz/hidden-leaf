shader_type spatial;
render_mode cull_back;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 pigment : source_color = vec4(0.68, 0.56, 0.40, 1.0);
uniform float metres_per_repeat = 3.0;
uniform float scan_weight = 0.55;
uniform float relief = 0.28;
uniform float roughness = 0.88;
uniform float moisture = 0.0;
uniform float mineral = 0.0;
uniform float patch_wear = 0.0;
varying vec3 world_position;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    // Authored metre UVs replace per-pixel triplanar reconstruction.
    vec2 p=UV/metres_per_repeat;
    vec3 scan=texture(surface_color,p).rgb;
    float luminance=dot(scan,vec3(0.2126,0.7152,0.0722));
    float stain=noise(world_position.xz*0.12+vec2(world_position.y*0.035));
    float foot=1.0-smoothstep(0.0,1.4,world_position.y);
    // Metre-scale coherent weather fronts and vertical runoff break scan tiling.
    vec2 wall=world_position.xz+vec2(world_position.y*0.43,world_position.y*0.71);
    float broad=noise(wall*0.075);
    float medium=noise(wall*0.31+vec2(19.3,7.1));
    float grain=noise(wall*1.13);
    float patches=smoothstep(0.36,0.67,broad*0.56+medium*0.32+grain*0.12);
    float runoff=noise(world_position.xz*1.4+vec2(world_position.y*0.025));
    float weather=1.0-patch_wear*(0.13*broad+0.055*runoff);
    float wear_mix=scan_weight*mix(1.0,0.05+0.95*patches,patch_wear);
    vec3 surface=mix(vec3(luminance),scan,mineral);
    ALBEDO=pigment.rgb*mix(vec3(1.0),clamp(surface*2.8,vec3(0.32),vec3(1.7)),wear_mix)*(0.99-0.11*stain-0.10*foot)*weather;
    ROUGHNESS=clamp(mix(roughness,texture(surface_roughness,p).r,0.55)-moisture*foot*0.2,0.15,1.0);
    NORMAL_MAP=texture(surface_normal,p).rgb;
    NORMAL_MAP_DEPTH=relief*mix(1.0,0.04+0.24*patches,patch_wear);
}
