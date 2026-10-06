shader_type spatial;

uniform float height = 64.0;
uniform vec2 texture_scale = vec2(32.0, 32.0);

// Các texture từ res://assets/textures/
uniform sampler2D tex_dirt_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_2 : source_color, filter_linear_mipmap, repeat_enable;

uniform sampler2D color_gradient;

void fragment() {
	// Lấy tọa độ đỉnh trong không gian Model (cục bộ)
	vec4 world_vertex = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 model_vertex = (inverse(MODEL_MATRIX) * world_vertex).xyz;
	
	// Chuẩn hóa độ cao về khoảng [0.0, 1.0]
	float h_weight = clamp((model_vertex.y / height) * 0.5 + 0.5, 0.0, 1.0);
	
	// Tiled UV cho texture lặp lại đều trên bề mặt địa hình
	vec2 tiled_uv = UV * texture_scale;
	
	// Đọc mẫu 4 texture
	vec3 dirt1  = texture(tex_dirt_1, tiled_uv).rgb;
	vec3 dirt2  = texture(tex_dirt_2, tiled_uv).rgb;
	vec3 grass1 = texture(tex_grass_1, tiled_uv).rgb;
	vec3 grass2 = texture(tex_grass_2, tiled_uv).rgb;
	
	// Blend chuyển tiếp tự nhiên theo độ cao bằng smoothstep
	vec3 col = dirt1;
	col = mix(col, dirt2, smoothstep(0.15, 0.35, h_weight));
	col = mix(col, grass1, smoothstep(0.40, 0.65, h_weight));
	col = mix(col, grass2, smoothstep(0.70, 0.90, h_weight));
	
	ALBEDO = col;
	// Không gán NORMAL_MAP khi chưa có texture normal map thật,
	// để Godot tự dùng normal mượt mà của đỉnh (vertex normal).
}
