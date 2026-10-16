extends SceneTree

func _init() -> void:
	var src_anim: Animation = load("res://animations/basic/Melee_Unarmed_Attack_Punch_A.res") as Animation
	if not src_anim:
		print("Failed to load Melee_Unarmed_Attack_Punch_A.res")
		quit()
		return

	var new_anim := Animation.new()
	new_anim.resource_name = "Melee_Unarmed_Attack_Punch_B"
	new_anim.length = 0.75
	new_anim.loop_mode = Animation.LOOP_NONE

	# Snappy timing for Hit 2 of the 2-hit punch combo:
	# 0.00 -> 0.15s: Quick windup (maps from 0.00 to 0.35s of Punch A)
	# 0.15 -> 0.32s: Left fist punch strike (maps from 0.35s to 0.55s of Punch A)
	# 0.32 -> 0.75s: Retract left fist back to guard (maps from 0.55s to 1.16s of Punch A)
	var sample_src_time = func(nt: float) -> float:
		if nt <= 0.15:
			var factor: float = nt / 0.15
			var curved: float = factor * factor
			return lerpf(0.00, 0.35, curved)
		elif nt <= 0.32:
			var factor: float = (nt - 0.15) / (0.32 - 0.15)
			var curved: float = factor * factor * (3.0 - 2.0 * factor)
			return lerpf(0.35, 0.55, curved)
		else:
			var factor: float = (nt - 0.32) / (0.75 - 0.32)
			var curved: float = (1.0 - cos(factor * PI)) * 0.5
			return lerpf(0.55, 1.16, curved)

	var mirror_path = func(p: NodePath) -> NodePath:
		var s := str(p)
		if s.ends_with(".l"):
			return NodePath(s.substr(0, s.length() - 2) + ".r")
		elif s.ends_with(".r"):
			return NodePath(s.substr(0, s.length() - 2) + ".l")
		return p

	var num_samples := 31
	var step: float = new_anim.length / float(num_samples - 1)

	for src_track_idx in range(src_anim.get_track_count()):
		var orig_path := src_anim.track_get_path(src_track_idx)
		var target_path: NodePath = mirror_path.call(orig_path)
		var type := src_anim.track_get_type(src_track_idx)

		var new_track_idx := new_anim.add_track(type)
		new_anim.track_set_path(new_track_idx, target_path)
		new_anim.track_set_interpolation_type(new_track_idx, src_anim.track_get_interpolation_type(src_track_idx))

		for s_i in range(num_samples):
			var new_t: float = float(s_i) * step
			var src_t: float = sample_src_time.call(new_t)

			var val
			match type:
				Animation.TYPE_POSITION_3D:
					var p: Vector3 = src_anim.position_track_interpolate(src_track_idx, src_t)
					val = Vector3(-p.x, p.y, p.z)
				Animation.TYPE_ROTATION_3D:
					var q: Quaternion = src_anim.rotation_track_interpolate(src_track_idx, src_t)
					val = Quaternion(q.x, -q.y, -q.z, q.w)
				Animation.TYPE_SCALE_3D:
					val = src_anim.scale_track_interpolate(src_track_idx, src_t)
				Animation.TYPE_VALUE:
					val = src_anim.value_track_interpolate(src_track_idx, src_t)
				_:
					if src_anim.track_get_key_count(src_track_idx) > 0:
						val = src_anim.track_get_key_value(src_track_idx, 0)

			if val != null:
				new_anim.track_insert_key(new_track_idx, new_t, val)

	var save_path := "res://animations/basic/Melee_Unarmed_Attack_Punch_B.res"
	var err := ResourceSaver.save(new_anim, save_path)
	if err == OK:
		print("Successfully saved ", save_path)
	else:
		print("Error saving Punch B: ", err)

	# Update skeleton.res
	var lib: AnimationLibrary = load("res://animations/enemies/skeletons/skeleton.res") as AnimationLibrary
	if lib:
		if lib.has_animation("Melee_Unarmed_Attack_Punch_B"):
			lib.remove_animation("Melee_Unarmed_Attack_Punch_B")
		lib.add_animation("Melee_Unarmed_Attack_Punch_B", new_anim)
		var lib_err := ResourceSaver.save(lib, "res://animations/enemies/skeletons/skeleton.res")
		if lib_err == OK:
			print("Successfully added Melee_Unarmed_Attack_Punch_B to skeleton.res!")
		else:
			print("Error saving skeleton.res: ", lib_err)
	quit()
