class_name SkeletonMinion
extends SkeletonBase

func _ready() -> void:
	super._ready()

func _perform_attack() -> void:
	super._perform_attack()

func _die() -> void:
	super._die()
	queue_free()
