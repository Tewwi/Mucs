extends SceneTree

func _init() -> void:
	var src_anim: Animation = load("res://animations/basic/Melee_1H_Attack_Slice_Diagonal.res") as Animation
	if not src_anim:
		print("Failed to load source animation")
		quit()
		return

	var new_anim := Animation.new()
	new_anim.resource_name = "Melee_1H_Attack_Slice_Diagonal_Reverse"
	# Length: 1.0s (kéo dài thành 1.0s theo yêu cầu)
	# 0.0s -> 0.40s: Vung chém hất chéo ngược từ dưới trái lên trên phải (từ 0.55 về 0.33 của anim gốc)
	# 0.40s -> 1.00s: Thu đà kiếm từ trên phải trở về tư thế chuẩn bị Idle (từ 0.33 về 0.00 của anim gốc)
	new_anim.length = 1.0
	new_anim.loop_mode = Animation.LOOP_NONE

	var sample_src_time = func(nt: float) -> float:
		if nt <= 0.40:
			var factor: float = nt / 0.40 # 0 -> 1
			# Smooth cubic easing cho cú chém hất ngược
			var curved: float = factor * factor * (3.0 - 2.0 * factor)
			return lerpf(0.55, 0.33, curved)
		else:
			var factor: float = (nt - 0.40) / (1.00 - 0.40) # 0 -> 1
			# Smooth cosine easing thu hồi kiếm về Ready pose
			var curved: float = (1.0 - cos(factor * PI)) * 0.5
			return lerpf(0.33, 0.00, curved)

	var num_samples := 31
	var step: float = new_anim.length / float(num_samples - 1)

	for track_idx in range(src_anim.get_track_count()):
		var path := src_anim.track_get_path(track_idx)
		var type := src_anim.track_get_type(track_idx)
		var new_track := new_anim.add_track(type)
		new_anim.track_set_path(new_track, path)
		new_anim.track_set_interpolation_type(new_track, src_anim.track_get_interpolation_type(track_idx))

		for sample_i in range(num_samples):
			var new_t: float = float(sample_i) * step
			var src_t: float = sample_src_time.call(new_t)

			var val
			match type:
				Animation.TYPE_POSITION_3D:
					val = src_anim.position_track_interpolate(track_idx, src_t)
				Animation.TYPE_ROTATION_3D:
					val = src_anim.rotation_track_interpolate(track_idx, src_t)
				Animation.TYPE_SCALE_3D:
					val = src_anim.scale_track_interpolate(track_idx, src_t)
				Animation.TYPE_VALUE:
					val = src_anim.value_track_interpolate(track_idx, src_t)
				_:
					if src_anim.track_get_key_count(track_idx) > 0:
						val = src_anim.track_get_key_value(track_idx, 0)
			
			if val != null:
				new_anim.track_insert_key(new_track, new_t, val)

	print("New 1.0s anim generated! Length: ", new_anim.length, ", Tracks: ", new_anim.get_track_count())
	var save_path := "res://animations/basic/Melee_1H_Attack_Slice_Diagonal_Reverse.res"
	var err := ResourceSaver.save(new_anim, save_path)
	if err == OK:
		print("Successfully saved: ", save_path)
	else:
		print("Error saving: ", err)

	# Update skeleton.res
	var lib: AnimationLibrary = load("res://animations/enemies/skeletons/skeleton.res") as AnimationLibrary
	if lib:
		if lib.has_animation("Melee_1H_Attack_Slice_Diagonal_Reverse"):
			lib.remove_animation("Melee_1H_Attack_Slice_Diagonal_Reverse")
		lib.add_animation("Melee_1H_Attack_Slice_Diagonal_Reverse", new_anim)
		var lib_err := ResourceSaver.save(lib, "res://animations/enemies/skeletons/skeleton.res")
		if lib_err == OK:
			print("Successfully updated skeleton.res with 1.0s animation!")
		else:
			print("Error saving skeleton.res: ", lib_err)
	quit()
