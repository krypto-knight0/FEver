shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
	COLOR = vec4(textureLod(screen_texture, SCREEN_UV, 2.0).rgb * 0.68, 1.0);
}
