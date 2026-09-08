shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaf_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 leaf_tint : source_color = vec3(0.97, 1.0, 0.95);
void vertex() {
    vec3 world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    float flex=pow(clamp(VERTEX.y/4.56,0.0,1.0),1.8);
    float slow=sin(TIME*.91+world_pos.x*.18+world_pos.z*.16);
    float flutter=sin(TIME*3.7+VERTEX.x*15.0+VERTEX.z*18.0);
    VERTEX.x+=(slow*.019+flutter*.003)*flex;
    VERTEX.z+=cos(TIME*.74+world_pos.z*.17)*.012*flex;
}
void fragment() {
    vec4 leaf=texture(leaf_color,UV);
    ALBEDO=leaf.rgb*leaf_tint;
    ALPHA=leaf.a;
    ALPHA_SCISSOR_THRESHOLD=.34;
    ROUGHNESS=.86;
    NORMAL_MAP=texture(leaf_normal,UV).rgb;
    NORMAL_MAP_DEPTH=.35;
    BACKLIGHT=leaf.rgb*.23;
}
