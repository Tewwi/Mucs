extends CharacterBody3D

const JUMP_VELOCITY = 4.5

@export_group("Camera Settings")
@export var mouse_sensitivity := 0.003
@export var min_pitch := -60.0 # Góc nhìn xuống tối đa (độ)
@export var max_pitch := 60.0 # Góc nhìn lên tối đa (độ)

@export_group("Player Controller")
@export var move_speed := 6.0
@export var acceleration := 20.0

var _camera_input_dir := Vector2.ZERO

@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera: Camera3D = %Camera3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape_focus"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("left_click"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion := (event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	if is_camera_motion:
		_camera_input_dir += event.relative * mouse_sensitivity

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Hướng di chuyển phụ thuộc vào góc quay của Camera (Yaw)
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (Vector3(input_dir.x, 0, input_dir.y)).rotated(Vector3.UP, camera_pivot.global_rotation.y).normalized()
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	handle_camera()
	move_and_slide()

func handle_camera() -> void:
	# Xoay camera theo chuyển động chuột
	camera_pivot.rotation.x -= _camera_input_dir.y
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	camera_pivot.rotation.y -= _camera_input_dir.x

	_camera_input_dir = Vector2.ZERO
