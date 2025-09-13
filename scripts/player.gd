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

# VAPI Voice Integration
var recording: AudioStreamWAV
var stereo := true
var mix_rate := 44100
var format := AudioStreamWAV.FORMAT_16_BITS

# Vapi configuration - replace with your actual values
var vapi_api_key := "6bc49d0f-26d9-45b0-8686-f16d12d76cac"
var vapi_assistant_id := "f3cf5bf5-335f-44a6-b9dd-3c9b09eb0c0b"
var http_request: HTTPRequest
var websocket: WebSocketPeer
var websocket_url: String = ""
var is_websocket_connected: bool = false
var vapi_audio_player: AudioStreamPlayer
var audio_stream_generator: AudioStreamGenerator
var audio_stream_playback: AudioStreamGeneratorPlayback
var is_streaming_vapi_audio: bool = false
var is_vapi_recording: bool = false

# Audio capture for real-time streaming
var audio_capture_bus_index: int
var audio_input: AudioEffectCapture


func _ready():
	# Capture the mouse for first-person controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Store the camera's original position for bobbing
	camera_original_position = camera.position
	# Store the camera's base FOV
	camera_base_fov = camera.fov
	
	# Initialize VAPI components
	setup_vapi_components()


func _input(event):
	# Handle mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -VERTICAL_LOOK_LIMIT, VERTICAL_LOOK_LIMIT)
	
	# Toggle mouse capture with Escape key
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Toggle VAPI recording with T key
	if Input.is_action_just_pressed("ui_accept") and Input.is_key_pressed(KEY_T):
		toggle_vapi_recording()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_T:
		toggle_vapi_recording()


func _physics_process(delta: float) -> void:
	handle_vapi_updates()
	
	# Get the input direction
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var moving_forward = input_dir.y > 0.0
	var moving_backward = input_dir.y < 0.0
	var moving_sideways = abs(input_dir.x) > 0.0

	# Correct running condition: only run when moving forward
	var is_running = Input.is_action_pressed("run") and current_stamina > 0 and moving_forward
	var current_speed = RUN_SPEED if is_running else WALK_SPEED

	# Apply movement multipliers only if not moving forward
	var speed_multiplier = 1.0
	if not moving_forward:
		if moving_backward:
			speed_multiplier = 0.75
		elif moving_sideways:
			speed_multiplier = 0.9
	current_speed *= speed_multiplier

	# Handle stamina
	if is_running and velocity.length() > 0.1:
		current_stamina = max(0, current_stamina - STAMINA_DRAIN_RATE * delta)
	else:
		current_stamina = min(MAX_STAMINA, current_stamina + STAMINA_REGEN_RATE * delta)

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# View bobbing
	handle_view_bobbing(delta, is_running)
	handle_fov_scaling(delta)

	move_and_slide()


func handle_fov_scaling(delta: float):
	var forward_dir = -transform.basis.z.normalized()
	var forward_speed = velocity.dot(forward_dir)
	var speed_factor = clamp(forward_speed / RUN_SPEED, -1.0, 1.0)
	var target_fov = camera_base_fov * (1.0 + speed_factor * FOV_CHANGE_AMOUNT)
	camera.fov = lerp(camera.fov, target_fov, FOV_CHANGE_SPEED * delta)


func handle_view_bobbing(delta: float, is_running: bool):
	if velocity.length() > 0.1 and is_on_floor():
		var bob_amplitude = BOB_AMPLITUDE_RUN if is_running else BOB_AMPLITUDE
		bob_time += delta * velocity.length() * BOB_FREQUENCY
		var vertical_bob = sin(bob_time * 2) * bob_amplitude
		var horizontal_bob = sin(bob_time) * bob_amplitude * 0.3
		var bob_offset = Vector3(horizontal_bob, vertical_bob, 0)
		camera.position = camera_original_position + bob_offset
	else:
		bob_time = 0.0
		camera.position = camera.position.lerp(camera_original_position, delta * 5.0)


# Getter functions
func get_stamina_percentage() -> float:
	return (current_stamina / MAX_STAMINA) * 100.0

func get_current_stamina() -> float:
	return current_stamina

func get_max_stamina() -> float:
	return MAX_STAMINA


# -----------------------
# VAPI Voice Integration
# -----------------------
func setup_vapi_components():
	# Setup audio capture bus
	audio_capture_bus_index = AudioServer.get_bus_index("Record")
	if audio_capture_bus_index == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		audio_capture_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(audio_capture_bus_index, "Record")
	
	# Mute the Record bus to prevent feedback
	AudioServer.set_bus_mute(audio_capture_bus_index, true)
	
	# Add capture effect to Record bus
	audio_input = AudioEffectCapture.new()
	AudioServer.add_bus_effect(audio_capture_bus_index, audio_input)
	AudioServer.set_bus_volume_db(audio_capture_bus_index, 0)
	
	# Setup microphone input to Record bus
	var microphone_player = AudioStreamPlayer.new()
	microphone_player.bus = "Record"
	add_child(microphone_player)
	var microphone_stream = AudioStreamMicrophone.new()
	microphone_player.stream = microphone_stream
	microphone_player.play()  # Start capturing microphone input
	
	# Initialize HTTPRequest
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_vapi_request_completed)
	
	# Initialize WebSocket
	websocket = WebSocketPeer.new()
	
	# Initialize streaming audio for AI responses
	audio_stream_generator = AudioStreamGenerator.new()
	audio_stream_generator.mix_rate = mix_rate
	audio_stream_generator.buffer_length = 1.0
	
	vapi_audio_player = AudioStreamPlayer.new()
	add_child(vapi_audio_player)
	vapi_audio_player.stream = audio_stream_generator
	vapi_audio_player.volume_db = 0.0
	
	print("VAPI components initialized with microphone capture")


func toggle_vapi_recording():
	if is_vapi_recording:
		stop_vapi_recording()
	else:
		start_vapi_recording()


func start_vapi_recording():
	if vapi_api_key == "YOUR_API_KEY" or vapi_assistant_id == "YOUR_ASSISTANT_ID":
		print("Please configure your Vapi API key and assistant ID")
		return
	
	if not is_vapi_recording:
		is_vapi_recording = true
		audio_input.clear_buffer()
		print("Started VAPI recording...")
		call_vapi_api()


func stop_vapi_recording():
	if is_vapi_recording:
		is_vapi_recording = false
		if is_websocket_connected:
			send_control_message({"type": "hangup"})
			websocket.close()
			is_websocket_connected = false
		stop_vapi_audio_stream()
		print("Stopped VAPI recording")


func handle_vapi_updates():
	if not websocket:
		return
		
	websocket.poll()
	var state: WebSocketPeer.State = websocket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN and not is_websocket_connected:
		is_websocket_connected = true
		print("WebSocket connected successfully!")
	elif state == WebSocketPeer.STATE_CLOSED and is_websocket_connected:
		is_websocket_connected = false
		print("WebSocket connection closed")
	
	# Incoming messages
	if is_websocket_connected:
		while websocket.get_available_packet_count() > 0:
			var packet: PackedByteArray = websocket.get_packet()
			if packet.size() > 0:
				var text = packet.get_string_from_utf8()
				if text.begins_with("{") or text.begins_with("["):
					handle_control_message(text)
				else:
					handle_incoming_audio(packet)
	
	# Send mic audio
	if is_websocket_connected and is_vapi_recording:
		send_realtime_audio_to_websocket()


func call_vapi_api():
	var payload: Dictionary = {
		"assistantId": vapi_assistant_id,
		"transport": {
			"provider": "vapi.websocket",
			"audioFormat": {
				"format": "pcm_s16le",
				"container": "raw",
				"sampleRate": mix_rate
			}
		}
	}
	var json_string = JSON.stringify(payload)
	var headers = [
		"Authorization: Bearer " + vapi_api_key,
		"Content-Type: application/json"
	]
	
	print("Making Vapi API call...")
	http_request.request("https://api.vapi.ai/call", headers, HTTPClient.METHOD_POST, json_string)


func _on_vapi_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	print("Vapi API Response Code: ", response_code)
	if response_code != 200 and response_code != 201:
		print("API request failed")
		return
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("Failed to parse JSON")
		return
	
	var data = json.data
	if data.has("transport") and data["transport"].has("websocketCallUrl"):
		websocket_url = data["transport"]["websocketCallUrl"]
		var err = websocket.connect_to_url(websocket_url)
		if err != OK:
			print("Failed to connect to WebSocket")
	else:
		print("WebSocket URL not found")


func send_realtime_audio_to_websocket():
	if not is_websocket_connected or not audio_input:
		return
	
	var frames_available = audio_input.get_frames_available()
	if frames_available == 0:
		return
	
	var audio_frames = audio_input.get_buffer(frames_available)
	var pcm_data = PackedByteArray()
	
	# Convert audio frames to raw PCM data (same format as incoming audio)
	for frame in audio_frames:
		# Convert to mono by averaging stereo channels
		var mono_sample = (frame.x + frame.y) / 2.0
		
		# Convert to 16-bit signed integer (same as incoming audio format)
		var int_sample = int(clamp(mono_sample * 32767.0, -32768.0, 32767.0))
		
		# Pack as little-endian 16-bit (same as received audio format)
		pcm_data.append(int_sample & 0xFF)          # Low byte
		pcm_data.append((int_sample >> 8) & 0xFF)   # High byte
	
	# Send raw PCM binary data directly (same as received audio handling)
	if pcm_data.size() > 0:
		var error = websocket.send(pcm_data, WebSocketPeer.WRITE_MODE_BINARY)
		if error != OK:
			print("Failed to send raw PCM audio: ", error)
		else:
			print("Sent ", pcm_data.size(), " bytes of raw PCM data")


func send_control_message(message_obj: Dictionary):
	if is_websocket_connected and websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		websocket.send(JSON.stringify(message_obj).to_utf8_buffer(), WebSocketPeer.WRITE_MODE_TEXT)


func handle_control_message(json_text: String):
	var json = JSON.new()
	if json.parse(json_text) != OK:
		print("Failed to parse control message")
		return
	
	var message = json.data
	if message.has("type"):
		match message["type"]:
			"call-started":
				print("Call started")
			"call-ended":
				print("Call ended")
				stop_vapi_recording()
			_:
				print("Unknown message type: ", message["type"])


func handle_incoming_audio(audio_data: PackedByteArray):
	if not is_streaming_vapi_audio:
		start_vapi_audio_stream()
	push_audio_to_continuous_stream(audio_data)


func start_vapi_audio_stream():
	if not is_streaming_vapi_audio:
		vapi_audio_player.play()
		audio_stream_playback = vapi_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
		is_streaming_vapi_audio = true
		print("Started Vapi audio stream")


func push_audio_to_continuous_stream(audio_data: PackedByteArray):
	if not audio_stream_playback:
		return
	
	var samples = PackedFloat32Array()
	for i in range(0, audio_data.size(), 2):
		if i + 1 < audio_data.size():
			var s = audio_data[i] | (audio_data[i + 1] << 8)
			if s >= 32768:
				s -= 65536
			samples.append(float(s) / 32768.0)
	
	var available_frames = audio_stream_playback.get_frames_available()
	var push_count = min(samples.size(), available_frames)
	for i in range(push_count):
		audio_stream_playback.push_frame(Vector2(samples[i], samples[i]))


func stop_vapi_audio_stream():
	if is_streaming_vapi_audio:
		vapi_audio_player.stop()
		is_streaming_vapi_audio = false
		audio_stream_playback = null
		print("Stopped Vapi audio stream")
