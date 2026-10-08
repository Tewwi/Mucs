extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var _log_timer: float = 0.0
const LOG_INTERVAL := 0.25 # In log trạng thái 4 lần / giây


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# --- BẮT ĐẦU ĐO LƯỜNG & CHẨN ĐOÁN MOVE_AND_SLIDE ---
	_log_timer += delta
	var should_log := _log_timer >= LOG_INTERVAL
	if should_log:
		_log_timer = 0.0
		print("[Player] >> BẮT ĐẦU move_and_slide | Pos: (%.1f, %.1f, %.1f) | Vel: (%.1f, %.1f, %.1f) | OnFloor: %s" % [
			global_position.x, global_position.y, global_position.z,
			velocity.x, velocity.y, velocity.z,
			is_on_floor()
		])

	var t0 := Time.get_ticks_usec()
	move_and_slide()
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	if should_log:
		print("[Player] << KẾT THÚC move_and_slide | Mất: %.2f ms | Pos mới: (%.1f, %.1f, %.1f) | Collisions: %d" % [
			elapsed_ms,
			global_position.x, global_position.y, global_position.z,
			get_slide_collision_count()
		])
	elif elapsed_ms > 5.0:
		# Bắt các frame bị giật lag đột ngột bất thường
		print("[Player] !! CẢNH BÁO LAG !! move_and_slide mất tới %.2f ms tại Pos: (%.1f, %.1f, %.1f)" % [
			elapsed_ms,
			global_position.x, global_position.y, global_position.z
		])
