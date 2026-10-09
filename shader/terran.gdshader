shader_type spatial;

uniform float height = 64.0;
uniform vec2 texture_scale = vec2(32.0, 32.0);

// Các texture từ res://assets/textures/
uniform sampler2D tex_dirt_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_2 : source_color, filter_linear_mipmap, repeat_enable;

// Texture dành riêng cho vách núi dốc đứng (Cliff / Rock)
uniform sampler2D tex_cliff : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms Cliff_Slope;
// Ngưỡng độ dốc bắt đầu biến thành vách núi (1.0 = phẳng hoàn toàn, 0.0 = dốc đứng 90 độ)
uniform float cliff_slope_threshold : hint_range(0.0, 1.0) = 0.65;
// Độ mượt chuyển tiếp giữa nền đất/cỏ và vách đá
uniform float cliff_blend_range : hint_range(0.01, 0.5) = 0.15;
// Độ lặp lại của texture trên vách đá
uniform float cliff_texture_scale = 16.0;
group_uniforms;

uniform sampler2D color_gradient;

void fragment() {
	// Lấy tọa độ đỉnh trong không gian Model (cục bộ)
	vec4 world_vertex = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 model_vertex = (inverse(MODEL_MATRIX) * world_vertex).xyz;
	
	// Pháp tuyến bề mặt trong World Space để đo độ dốc chính xác
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	
	// Chuẩn hóa độ cao về khoảng [0.0, 1.0]
	float h_weight = clamp((model_vertex.y / height) * 0.5 + 0.5, 0.0, 1.0);
	
	// Tiled UV cho texture lặp lại đều trên bề mặt địa hình
	vec2 tiled_uv = UV * texture_scale;
	
	// Đọc mẫu 4 texture độ cao cơ bản
	vec3 dirt1  = texture(tex_dirt_1, tiled_uv).rgb;
	vec3 dirt2  = texture(tex_dirt_2, tiled_uv).rgb;
	vec3 grass1 = texture(tex_grass_1, tiled_uv).rgb;
	vec3 grass2 = texture(tex_grass_2, tiled_uv).rgb;
	
	// Blend chuyển tiếp tự nhiên theo độ cao bằng smoothstep
	vec3 col = dirt1;
	col = mix(col, dirt2, smoothstep(0.15, 0.35, h_weight));
	col = mix(col, grass1, smoothstep(0.40, 0.65, h_weight));
	col = mix(col, grass2, smoothstep(0.70, 0.90, h_weight));
	
	// Đọc texture vách đá theo 2 trục đứng X/Z (Bi-planar) để triệt tiêu hiện tượng kéo giãn (stretching)
	vec2 cliff_uv_x = model_vertex.zy * (cliff_texture_scale / height);
	vec2 cliff_uv_z = model_vertex.xy * (cliff_texture_scale / height);
	vec3 cliff_sample_x = texture(tex_cliff, cliff_uv_x).rgb;
	vec3 cliff_sample_z = texture(tex_cliff, cliff_uv_z).rgb;
	float weight_x = abs(world_normal.x);
	float weight_z = abs(world_normal.z);
	vec3 cliff_col = mix(cliff_sample_z, cliff_sample_x, weight_x / max(weight_x + weight_z, 0.001));
	
	// Tính trọng số độ dốc: world_normal.y càng nhỏ thì bề mặt càng dựng đứng -> cliff_factor càng cao
	float cliff_factor = 1.0 - smoothstep(cliff_slope_threshold - cliff_blend_range, cliff_slope_threshold + cliff_blend_range, world_normal.y);
	
	// Áp dụng texture vách núi đè lên các vùng dốc đứng
	col = mix(col, cliff_col, cliff_factor);
	
	ALBEDO = col;
	// Không gán NORMAL_MAP khi chưa có texture normal map thật,
	// để Godot tự dùng normal mượt mà của đỉnh (vertex normal).
}
