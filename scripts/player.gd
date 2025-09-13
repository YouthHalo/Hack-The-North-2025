extends CharacterBody3D


const WALK_SPEED = 5.0
const RUN_SPEED = 8.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const VERTICAL_LOOK_LIMIT = 1.5 # Approximately 85 degrees

# Stamina system
const MAX_STAMINA = 100.0
const STAMINA_DRAIN_RATE = 25.0  # Stamina per second while running
const STAMINA_REGEN_RATE = 15.0  # Stamina per second while not running
var current_stamina = MAX_STAMINA

# View bobbing
const BOB_FREQUENCY = 2.0
const BOB_AMPLITUDE = 0.08
const BOB_AMPLITUDE_RUN = 0.12
var bob_time = 0.0

@onready var camera: Camera3D = $Camera3D

var camera_original_position: Vector3
var camera_base_fov: float
const FOV_CHANGE_AMOUNT = 0.4  # 10% FOV change
const FOV_CHANGE_SPEED = 2.0   # How fast FOV changes


func _ready():
	# Capture the mouse for first-person controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Store the camera's original position for bobbing
	camera_original_position = camera.position
	# Store the camera's base FOV
	camera_base_fov = camera.fov


func _input(event):
	# Handle mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate the player horizontally
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		
		# Rotate the camera vertically
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		
		# Clamp the camera's vertical rotation to prevent over-rotation
		camera.rotation.x = clamp(camera.rotation.x, -VERTICAL_LOOK_LIMIT, VERTICAL_LOOK_LIMIT)
	
	# Toggle mouse capture with Escape key
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	# Get the input direction

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var moving_forward = input_dir.y > 0.0
	var moving_backward = input_dir.y < 0.0
	var moving_sideways = abs(input_dir.x) > 0.0

	# Only allow running if moving forward (even diagonally), never if moving backward
	var is_running = Input.is_action_pressed("run") and current_stamina > 0 and moving_backward and not moving_forward #it does the opposite of what it should????? why does this only allow running forward idk ima just cry in a corner
	var current_speed = RUN_SPEED if is_running else WALK_SPEED

	# Apply movement multipliers only if not moving forward
	var speed_multiplier = 1.0
	if not moving_forward:
		if moving_backward:
			speed_multiplier = 0.75
		elif moving_sideways:
			speed_multiplier = 0.9
	# If moving forward (even diagonally), ignore multipliers
	current_speed *= speed_multiplier

	# Handle stamina
	if is_running and velocity.length() > 0.1:
		current_stamina = max(0, current_stamina - STAMINA_DRAIN_RATE * delta)
	else:
		current_stamina = min(MAX_STAMINA, current_stamina + STAMINA_REGEN_RATE * delta)

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle movement
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# Handle view bobbing
	handle_view_bobbing(delta, is_running)

	# Handle FOV scaling based on forward/backward speed
	handle_fov_scaling(delta)

	move_and_slide()
# FOV scaling based on forward/backward speed
func handle_fov_scaling(delta: float):
	# Player's local forward is -transform.basis.z
	var forward_dir = -transform.basis.z.normalized()
	var forward_speed = velocity.dot(forward_dir)
	var max_speed = RUN_SPEED
	# Clamp factor between -1 (full back) and 1 (full forward)
	var speed_factor = clamp(forward_speed / max_speed, -1.0, 1.0)
	var target_fov = camera_base_fov * (1.0 + speed_factor * FOV_CHANGE_AMOUNT)
	camera.fov = lerp(camera.fov, target_fov, FOV_CHANGE_SPEED * delta)


func handle_view_bobbing(delta: float, is_running: bool):
	# Only bob when moving and on the ground
	if velocity.length() > 0.1 and is_on_floor():
		var bob_amplitude = BOB_AMPLITUDE_RUN if is_running else BOB_AMPLITUDE
		bob_time += delta * velocity.length() * BOB_FREQUENCY
		
		# Calculate bobbing offset with synchronized left/right motion
		var vertical_bob = sin(bob_time * 2) * bob_amplitude    # Up and down motion
		var horizontal_bob = sin(bob_time) * bob_amplitude * 0.3  # Left and right motion (peaks when vertical is at minimum)
		
		var bob_offset = Vector3(
			horizontal_bob,  # Left and right sway
			vertical_bob,    # Up and down motion
			0
		)
		
		camera.position = camera_original_position + bob_offset
	else:
		# Smoothly return to original position when not moving
		bob_time = 0.0
		camera.position = camera.position.lerp(camera_original_position, delta * 5.0)


# Getter functions for UI or other systems
func get_stamina_percentage() -> float:
	return (current_stamina / MAX_STAMINA) * 100.0

func get_current_stamina() -> float:
	return current_stamina

func get_max_stamina() -> float:
	return MAX_STAMINA
