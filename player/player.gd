extends CharacterBody2D


const speed = 50.0

func get_input():
	velocity = Vector2()
	if Input.is_action_pressed('ui_right'):
		velocity.x += 1
	if Input.is_action_pressed('ui_left'):
		velocity.x -= 1
	if Input.is_action_pressed('ui_down'):
		velocity.y += 1
	if Input.is_action_pressed('ui_up'):
		velocity.y -= 1
		
	velocity = velocity.normalized() * speed
	
	# Toggle CollisionShape2D with "ui_accept" action
	if Input.is_action_just_pressed("ui_accept"):
		$CollisionShape2D.disabled = !$CollisionShape2D.disabled
		
func _physics_process(delta):
	get_input()
	move_and_slide()
