extends Node3D

## Tín hiệu phát ra khi hoàn thành 1 chu kỳ ngày đêm
signal cycle_completed
## Tín hiệu phát ra khi chuyển sang giờ mới (0 - 23)
signal hour_changed(new_hour: int)

@export_group("Cycle Settings")
## Tổng thời gian cho 1 chu kỳ ngày đêm (tính bằng giây)
@export var cycle_duration: float = 60.0

## Bắt đầu từ thời điểm nào trong ngày khi game chạy (0.0 đến 24.0 giờ, mặc định 6.0 = 6:00 sáng)
@export_range(0.0, 24.0, 0.1) var start_hour: float = 6.0

## Bật / tạm dừng animation chu kỳ ngày đêm
@export var is_running: bool = true

## Góc xoay trục X bắt đầu và kết thúc (mặc định -180 đến 180 độ)
@export var min_angle: float = -180.0
@export var max_angle: float = 180.0

@export_group("Time Tracker (Kiểm tra & Theo dõi)")
## Bộ đếm thời gian đã trôi qua trong chu kỳ hiện tại (tính bằng giây, từ 0 đến cycle_duration)
@export var current_time: float = 0.0

## Đồng bộ thời gian trong ngày (tính theo giờ từ 0.0 đến 24.0) để bạn dễ kiểm tra
@export_range(0.0, 24.0, 0.01) var time_of_day: float = 0.0

## Tiến độ chu kỳ chuẩn hóa từ 0.0 (bắt đầu) đến 1.0 (kết thúc)
@export_range(0.0, 1.0, 0.001) var time_progress: float = 0.0

## Chuỗi hiển thị định dạng giờ:phút trực quan (ví dụ: "06:30", "12:00")
@export var formatted_time: String = "00:00"

var _last_hour: int = -1


func _ready() -> void:
	# Khởi tạo thời gian ban đầu theo start_hour
	if cycle_duration > 0.0:
		current_time = (start_hour / 24.0) * cycle_duration
	_update_cycle()


func _process(delta: float) -> void:
	if not is_running or cycle_duration <= 0.0:
		return
	
	# Cập nhật bộ đếm thời gian
	current_time += delta
	if current_time >= cycle_duration:
		current_time = fmod(current_time, cycle_duration)
		cycle_completed.emit()
	elif current_time < 0.0:
		current_time = cycle_duration - fmod(abs(current_time), cycle_duration)
	
	_update_cycle()


## Cập nhật góc xoay trục X và đồng bộ các biến thời gian
func _update_cycle() -> void:
	if cycle_duration <= 0.0:
		return
	
	# Tính tiến độ trong ngày từ 0.0 đến 1.0
	time_progress = clampf(current_time / cycle_duration, 0.0, 1.0)
	
	# Xoay trục X từ min_angle (-180 deg) đến max_angle (180 deg)
	rotation_degrees.x = lerpf(min_angle, max_angle, time_progress)
	
	# Đồng bộ thời gian ra dạng giờ (0.0 đến 24.0h)
	time_of_day = time_progress * 24.0
	
	# Định dạng chuỗi hiển thị HH:MM để dễ kiểm tra
	var total_minutes: int = int(time_of_day * 60.0)
	var hours: int = (total_minutes / 60) % 24
	var minutes: int = total_minutes % 60
	formatted_time = "%02d:%02d" % [hours, minutes]
	
	# Phát tín hiệu khi bước sang giờ mới
	if hours != _last_hour:
		_last_hour = hours
		hour_changed.emit(hours)


## Hàm tiện ích: Đặt thời gian trực tiếp theo giờ (0.0 -> 24.0)
func set_time_by_hour(hour: float) -> void:
	if cycle_duration <= 0.0:
		return
	var normalized_hour: float = fmod(hour, 24.0)
	if normalized_hour < 0.0:
		normalized_hour += 24.0
	current_time = (normalized_hour / 24.0) * cycle_duration
	_update_cycle()


## Hàm tiện ích: Lấy tiến độ normalized (0.0 -> 1.0)
func get_progress() -> float:
	return time_progress
