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

# UI state nodes
@onready var item_open: Node = $"item/open"
@onready var item_closed: Node = $"item/closed"

# Subtitle system
@onready var subtitle_label: RichTextLabel = $"Ingame UI/Subtitles"
@onready var hint_label: RichTextLabel = $"Ingame UI/Hint"
var subtitle_timer: float = 0.0
var subtitle_clear_delay: float = 6.0
var has_pending_subtitles: bool = false
var intro_message_complete: bool = false
var intro_target_text: String = "just finish up alright"  # Key phrase to detect intro completion
var church_cleanup_target_text: String = "go clean up that old church"  # Key phrase to detect church cleanup directive
var last_transcript_bit: String = ""  # Store the last transcript piece for replacement logic

# Assistant switching system
var vapi_assistant_id_stall_1 := "5fe51e48-9286-47bb-aa24-dfaa8c1d62a7"
var vapi_assistant_id_stall_2 := "2716c2b3-905c-477e-9191-ea7b274e9079"
var vapi_assistant_id_progress := "d122f599-9549-448c-8c1a-9800c281d589"
var vapi_assistant_id_eerie := "9d7dcd32-446c-406d-950f-604d842f1c21"
var vapi_assistant_id_fin := "4d3f0409-63ff-4116-8330-185692f23196"
var user_silence_timer: float = 0.0
var user_silence_threshold: float = 15.0
var silence_timer_last_print: float = 0.0  # Track last time we printed silence timer
var has_switched_assistant: bool = false
var has_switched_to_progress: bool = false  # Track if we've switched to progress assistant
var has_switched_to_eerie: bool = false  # Track if we've switched to eerie assistant
var has_switched_to_fin: bool = false  # Track if we've switched to fin assistant
var current_assistant_level: int = 0  # 0 = first, 1 = stall_1, 2 = stall_2
var movement_disabled: bool = false  # Disable movement when near car after uh oh

# Final sequence
@onready var black_screen_overlay: ColorRect = $"Ingame UI/ColorRect"

# Audio feedback
var phone_ringing_player: AudioStreamPlayer
var phone_unavailable_player: AudioStreamPlayer
var is_t_button_disabled: bool = false

# Audio capture for real-time streaming
var audio_capture_bus_index: int
var audio_input: AudioEffectCapture

# Graffiti cleaning system
@onready var spray_raycast: RayCast3D = $Camera3D/RayCast3D
var spray_audio_player: AudioStreamPlayer
var violin_audio_player: AudioStreamPlayer
var graffiti_counter: int = 0
var graves_hidden: bool = false
var car_detected_after_graves: bool = false


func _ready():
	# Capture the mouse for first-person controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Store the camera's original position for bobbing
	camera_original_position = camera.position
	# Store the camera's base FOV
	camera_base_fov = camera.fov
	
	# Initialize VAPI components
	setup_vapi_components()
	
	# Initialize spray audio
	setup_spray_audio()
	
	# Set phone always on (show open state)
	set_phone_always_on()
	
	# Start VAPI call immediately
	start_vapi_recording()


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
		if not is_t_button_disabled:
			toggle_vapi_recording()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_T:
		if not is_t_button_disabled:
			toggle_vapi_recording()
	
	# Handle mouse clicks for graffiti cleaning
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			handle_graffiti_spray()


func _physics_process(delta: float) -> void:
	handle_vapi_updates()
	handle_subtitle_timer(delta)
	handle_user_silence_timer(delta)
	check_car_in_view()  # Check if car comes into view after graves are hidden
	
	# If movement is disabled, skip all input handling
	if movement_disabled:
		# Still apply gravity
		if not is_on_floor():
			velocity += get_gravity() * delta
		
		# Stop horizontal movement gradually
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		
		move_and_slide()
		return
	
	# Get the input direction
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var moving_forward = input_dir.y > 0.0
	var moving_backward = input_dir.y < 0.0
	var moving_sideways = abs(input_dir.x) > 0.0

	# Correct running condition: only run when moving forward
	var is_running = Input.is_action_pressed("run") and current_stamina > 0 and not moving_forward #does the opposite idk but it works dont touch
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
	AudioServer.set_bus_volume_db(audio_capture_bus_index, 0) #deadass the 2nd value feels like it does nothing but it works 

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
	
	# Setup phone audio feedback
	setup_phone_audio()
	
	print("VAPI components initialized with microphone capture")


func setup_phone_audio():
	"""Setup audio players for phone feedback sounds"""
	# Phone ringing audio player
	phone_ringing_player = AudioStreamPlayer.new()
	add_child(phone_ringing_player)
	var ringing_audio = load("res://assets/phone-ringing.mp3")  # Assuming .mp3 format
	if ringing_audio:
		#phone_ringing_player.stream = ringing_audio
		pass
	phone_ringing_player.volume_db = -5.0  # Slightly quieter
	
	# Phone unavailable audio player
	phone_unavailable_player = AudioStreamPlayer.new()
	add_child(phone_unavailable_player)
	var unavailable_audio = load("res://assets/unavailable-phone.mp3")  # Assuming .mp3 format
	if unavailable_audio:
		phone_unavailable_player.stream = unavailable_audio
	phone_unavailable_player.volume_db = -3.0
	
	print("Phone audio feedback initialized")


func handle_connection_lost():
	"""Handle when WebSocket connection is lost unexpectedly"""
	print("Connection lost - playing unavailable sound and ending call")
	
	# Stop any ongoing audio
	if phone_ringing_player and phone_ringing_player.playing:
		phone_ringing_player.stop()
	
	# Stop the call recording
	if is_vapi_recording:
		is_vapi_recording = false
	
	stop_vapi_audio_stream()
	
	# Play unavailable phone sound for 2 seconds
	if phone_unavailable_player and phone_unavailable_player.stream:
		phone_unavailable_player.play()
		
		# Wait for 2 seconds, then stop the audio
		await get_tree().create_timer(1.3).timeout
		phone_unavailable_player.stop()
		await get_tree().create_timer(0.5).timeout  # Small delay after sound
	
	# Switch phone call mode to off
	update_call_ui()  # Phone always shows open state
	print("Call mode switched to off due to connection loss")


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
		update_call_ui()  # Phone always shows open state
		
		# Play phone ringing sound while connecting
		if phone_ringing_player and phone_ringing_player.stream:
			phone_ringing_player.play()
			print("Playing phone ringing sound...")
		
		call_vapi_api()


func stop_vapi_recording():
	if is_vapi_recording:
		is_vapi_recording = false
		
		# Stop phone ringing if it's playing
		if phone_ringing_player and phone_ringing_player.playing:
			phone_ringing_player.stop()
		
		if is_websocket_connected:
			send_control_message({"type": "hangup"})
			websocket.close()
			is_websocket_connected = false
		stop_vapi_audio_stream()
		update_call_ui()  # Phone always shows open state
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
		print("WebSocket connection closed unexpectedly")
		handle_connection_lost()
	
	# Incoming messages
	if is_websocket_connected:
		while websocket.get_available_packet_count() > 0:
			var packet: PackedByteArray = websocket.get_packet()
			if packet.size() > 0:
				# Check if this is likely text data (JSON) by looking at first byte
				if packet[0] == 123 or packet[0] == 91:  # '{' or '[' ASCII values
					var text = packet.get_string_from_utf8()
					if text != "":  # Valid UTF-8 conversion
						handle_control_message(text)
					else:
						print("Failed to parse text message from packet")
				else:
					# Treat as binary audio data
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
			# print("Sent ", pcm_data.size(), " bytes of raw PCM data")
			pass


func send_control_message(message_obj: Dictionary):
	if is_websocket_connected and websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		websocket.send(JSON.stringify(message_obj).to_utf8_buffer(), WebSocketPeer.WRITE_MODE_TEXT)


func handle_control_message(json_text: String):
	var json = JSON.new()
	if json.parse(json_text) != OK:
		print("Failed to parse control message: ", json_text)
		return
	
	var message = json.data
	print("Received control message: ", json_text)  # Debug log all control messages
	
	if message.has("type"):
		match message["type"]:
			"call-started":
				print("Call started")
			"call-ended":
				print("Call ended by AI")
				handle_ai_hangup()
			"transcript":
				if message.has("role") and message["role"] == "assistant" and message.has("transcript"):
					add_subtitle(message["transcript"])
				elif message.has("role") and message["role"] == "user" and message.has("transcript"):
					add_user_message(message["transcript"])
				if message.has("text"):
					print("Transcript: ", message["text"])
				if message.has("user") and message["user"].has("text"):
					print("User said: ", message["user"]["text"])
				if message.has("assistant") and message["assistant"].has("text"):
					print("Assistant said: ", message["assistant"]["text"])
			"conversation-update":
				print("Conversation update received")
				# Don't reset silence timer on conversation updates - they happen even when user isn't speaking
			"speech-update":
				if message.has("status"):
					print("Speech status: ", message["status"])
			_:
				print("Unknown message type: ", message["type"])
	else:
		print("Message without type field: ", message)


func handle_ai_hangup():
	"""Handle when AI hangs up - play unavailable sound and disable T button temporarily"""
	print("AI hung up - playing unavailable sound")
	
	# Stop the call
	stop_vapi_recording()
	
	# Disable T button
	is_t_button_disabled = true
	
	# Play unavailable phone sound for 2 seconds
	if phone_unavailable_player and phone_unavailable_player.stream:
		phone_unavailable_player.play()
		
		# Wait for 2 seconds, then stop the audio
		await get_tree().create_timer(2.0).timeout
		phone_unavailable_player.stop()
		await get_tree().create_timer(0.5).timeout  # Small delay after sound
		
		is_t_button_disabled = false
		update_call_ui()  # Phone always shows open state
		print("T button re-enabled")


func handle_incoming_audio(audio_data: PackedByteArray):
	# Stop phone ringing when AI starts talking
	if phone_ringing_player and phone_ringing_player.playing:
		phone_ringing_player.stop()
		print("AI responded - stopped ringing")
	
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

func update_call_ui():
	"""Phone is always on - always show open state"""
	if item_open and item_closed:
		# Always show open, hide closed
		item_open.visible = true
		item_closed.visible = false

func set_phone_always_on():
	"""Set phone to always be in the on state"""
	if item_open and item_closed:
		item_open.visible = true
		item_closed.visible = false

func handle_subtitle_timer(delta: float):
	"""Handle subtitle clearing timer"""
	if has_pending_subtitles:
		subtitle_timer += delta
		if subtitle_timer >= subtitle_clear_delay:
			clear_subtitles()

func add_subtitle(text: String):
	"""Add subtitle text to the RichTextLabel"""
	if subtitle_label:
		var current_text = subtitle_label.text
		
		# Check if the new text is an extension/update of the current text
		# This handles VAPI's incremental transcript updates
		if current_text != "" and text.begins_with(current_text):
			# New text contains current text + more, so just replace entirely
			subtitle_label.text = text
			print("Updated subtitle with extended version")
		elif current_text != "" and current_text.length() > 0:
			# Check if new text is a partial update that should replace the end
			var words_current = current_text.split(" ")
			var words_new = text.split(" ")
			
			# Find overlap between end of current and beginning of new
			var overlap_found = false
			for i in range(min(words_current.size(), words_new.size())):
				var current_suffix = " ".join(words_current.slice(words_current.size() - i - 1))
				var new_prefix = " ".join(words_new.slice(0, i + 1))
				
				if current_suffix == new_prefix and i > 0:
					# Found overlap, replace the overlapping part
					var keep_part = " ".join(words_current.slice(0, words_current.size() - i - 1))
					if keep_part == "":
						subtitle_label.text = text
					else:
						subtitle_label.text = keep_part + " " + text
					overlap_found = true
					print("Replaced overlapping subtitle portion")
					break
			
			if not overlap_found:
				# No overlap found, append normally
				subtitle_label.text = current_text + " " + text
		else:
			# First subtitle or current text is empty
			subtitle_label.text = text
		
		# Store this transcript bit for future comparisons
		last_transcript_bit = text
		
		# Check if intro message is complete
		if not intro_message_complete and intro_target_text in subtitle_label.text.to_lower():
			intro_message_complete = true
			# Add voice prompt to hint label
			if hint_label:
				hint_label.text = "Reply with your voice!"
			print("Intro message complete - added voice prompt")
		
		# Check for church cleanup directive
		if church_cleanup_target_text in subtitle_label.text.to_lower():
			if hint_label:
				hint_label.text = "Go to the building"
			print("Church cleanup directive detected - added building hint")
		
		# Reset timer and mark as having pending subtitles
		subtitle_timer = 0.0
		has_pending_subtitles = true
		print("Added subtitle: ", text)

func add_user_message(text: String):
	"""Add user message to the hint box"""
	if hint_label:
		hint_label.text = text
		print("Added user message: ", text)
	
	# Reset silence timer when user speaks
	user_silence_timer = 0.0
	silence_timer_last_print = 0.0
	print("User spoke - silence timer reset")

func clear_subtitles():
	"""Clear all subtitle text"""
	if subtitle_label:
		subtitle_label.text = ""
	if hint_label:
		hint_label.text = ""
	has_pending_subtitles = false
	subtitle_timer = 0.0
	last_transcript_bit = ""  # Clear the last transcript bit
	# Don't reset intro_message_complete - we want to keep tracking user silence
	print("Cleared subtitles")

func handle_user_silence_timer(delta: float):
	"""Handle switching assistant based on different logic for stall vs progress"""
	# Apply timer for first assistant (level 0) and stall_1 (level 1)
	# But NOT if we've already switched to progress or eerie assistant
	if is_vapi_recording and intro_message_complete and current_assistant_level < 2 and not has_switched_to_progress and not has_switched_to_eerie:
		
		# For STALL assistants: use simple timer (no text-based logic)
		user_silence_timer += delta
		
		# Only print silence timer every 0.1 seconds
		if user_silence_timer - silence_timer_last_print >= 0.1:
			print("Silence timer: ", user_silence_timer, " / ", user_silence_threshold, " (Assistant level: ", current_assistant_level, ")")
			silence_timer_last_print = user_silence_timer
			
		if user_silence_timer >= user_silence_threshold:
			switch_to_next_assistant()

func switch_to_next_assistant():
	"""Switch to the next assistant after user silence"""
	if current_assistant_level >= 2 or has_switched_to_eerie:
		return  # Already at max level or eerie is active
		
	current_assistant_level += 1
	
	if current_assistant_level == 1:
		print("User has been silent for 20 seconds, switching to stall_1 assistant")
		vapi_assistant_id = vapi_assistant_id_stall_1
	elif current_assistant_level == 2:
		print("User has been silent for another 20 seconds, switching to stall_2 assistant")
		vapi_assistant_id = vapi_assistant_id_stall_2
	
	# Stop current call
	stop_vapi_recording()
	
	# Wait a moment then start with new assistant
	await get_tree().create_timer(1.0).timeout
	
	# Start new call with next assistant
	start_vapi_recording()
	
	# Reset timer for potential future switches
	user_silence_timer = 0.0


func switch_to_progress_assistant():
	"""Switch to progress assistant when graffiti is cleaned"""
	if has_switched_to_progress or has_switched_to_eerie:
		return  # Already switched or eerie is active
	
	has_switched_to_progress = true
	print("Graffiti cleaned! Waiting for conversation to pause before switching to progress assistant")
	
	# Wait for conversation to pause (only check text, not timer)
	while true:
		# Check if both subtitles and hint are empty (no text anywhere)
		var subtitles_empty = subtitle_label.text.strip_edges() == ""
		var hint_empty = hint_label.text.strip_edges() == ""
		var no_text_showing = subtitles_empty and hint_empty
		
		if no_text_showing:
			break
		
		await get_tree().create_timer(0.1).timeout
		print("Waiting for text to clear... (Subtitles empty: ", subtitles_empty, ", Hint empty: ", hint_empty, ")")
	
	print("All text cleared, now switching to progress assistant")
	
	# Switch to progress assistant
	vapi_assistant_id = vapi_assistant_id_progress
	
	# Stop current call
	stop_vapi_recording()
	
	# Wait a moment then start with progress assistant
	await get_tree().create_timer(1.0).timeout
	
	# Start new call with progress assistant
	start_vapi_recording()


func switch_to_eerie_assistant():
	"""Switch to eerie assistant 0.5 seconds after car detection"""
	if has_switched_to_eerie:
		return  # Already switched
	
	has_switched_to_eerie = true
	print("Car detected! Switching to eerie assistant in 0.5 seconds...")
	
	# Wait 0.5 seconds then switch
	#await get_tree().create_timer(0.5).timeout
	
	print("Switching to eerie assistant")
	
	# Switch to eerie assistant
	vapi_assistant_id = vapi_assistant_id_eerie
	
	# Stop current call
	stop_vapi_recording()
	
	# Wait a moment then start with eerie assistant
	await get_tree().create_timer(1.0).timeout
	
	# Start new call with eerie assistant
	start_vapi_recording()

func switch_to_fin_assistant():
	"""Switch to fin assistant immediately when player gets within 5 meters of car"""
	if has_switched_to_fin:
		return  # Already switched
	
	has_switched_to_fin = true
	movement_disabled = true  # Disable movement immediately
	print("Player near car! Switching to fin assistant IMMEDIATELY and disabling movement")
	
	# Switch to fin assistant
	vapi_assistant_id = vapi_assistant_id_fin
	
	# Stop current call
	stop_vapi_recording()
	
	# Start new call immediately with fin assistant
	start_vapi_recording()
	
	# After 0.3 seconds of fin speaking, end all calls and play unavailable phone sound
	await get_tree().create_timer(1.4).timeout
	end_calls_and_play_unavailable_phone()
	await get_tree().create_timer(0.5).timeout  # Small delay after sound
	# Gradually decrease 3D resolution (viewport scaling) to create a "low-res" effect
	var viewport = get_viewport()
	var start_scale = 1.0
	var end_scale = 0.01  # Really low resolution (20% of original)
	var duration = 2.0   # Duration in seconds for the effect
	var elapsed = 0.0

	while elapsed < duration:
		var t = elapsed / duration
		var scale = lerp(start_scale, end_scale, t)
		viewport.scaling_3d_scale = scale
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	viewport.scaling_3d_scale = end_scale
	print("3D resolution decreased to very low")

func end_calls_and_play_unavailable_phone():
	"""End all VAPI calls and play unavailable phone sound"""
	print("Ending all calls and playing unavailable phone sound")
	
	# Stop VAPI recording
	stop_vapi_recording()
	
	# Clear all text
	clear_subtitles()
	
	# Play unavailable phone sound
	if spray_audio_player:  # Reuse spray audio player for phone sound
		var unavailable_sound = load("res://assets/unavailable-phone.mp3")
		if unavailable_sound:
			spray_audio_player.stream = unavailable_sound
			spray_audio_player.play()
			print("Playing unavailable phone sound")
		else:
			print("Warning: Could not load unavailable-phone.mp3")
	
	# Wait a moment for the phone sound to play
	await get_tree().create_timer(2.0).timeout
	
	# Decrease 3D resolution to super low
	decrease_3d_resolution_dramatically()
	
	# Wait a moment then fade to black
	await get_tree().create_timer(1.0).timeout
	
	# Show black screen
	if black_screen_overlay:
		black_screen_overlay.visible = true
		print("Screen turned black")
	
	# Wait a moment in black screen
	await get_tree().create_timer(2.0).timeout
	
	# Shut off the game
	print("Shutting down game...")
	get_tree().quit()

func decrease_3d_resolution_dramatically():
	"""Dramatically decrease the 3D resolution"""
	print("Decreasing 3D resolution dramatically")
	var viewport = get_viewport()
	if viewport:
		# Set to very low resolution scale (0.1 = 10% of original resolution)
		viewport.scaling_3d_scale = 0.1
		print("3D resolution set to super low (10%)")


# -----------------------
# Graffiti Cleaning System
# -----------------------
func setup_spray_audio():
	"""Setup spray audio player for graffiti cleaning"""
	spray_audio_player = AudioStreamPlayer.new()
	add_child(spray_audio_player)
	var spray_audio = load("res://assets/spray.mp3")
	if spray_audio:
		spray_audio_player.stream = spray_audio
	spray_audio_player.volume_db = -9.0
	print("Spray audio initialized")
	
	# Setup violin audio player for car detection
	violin_audio_player = AudioStreamPlayer.new()
	add_child(violin_audio_player)
	var violin_audio = load("res://assets/violin.mp3")
	if violin_audio:
		violin_audio_player.stream = violin_audio
	violin_audio_player.volume_db = -9.0
	print("Violin audio initialized")


func handle_graffiti_spray():
	"""Handle mouse click for graffiti cleaning"""
	# Play spray sound
	if spray_audio_player and spray_audio_player.stream:
		spray_audio_player.play()
	
	# Check if raycast is hitting anything
	if spray_raycast and spray_raycast.is_colliding():
		var collider = spray_raycast.get_collider()
		var collision_point = spray_raycast.get_collision_point()
		var collision_normal = spray_raycast.get_collision_normal()
		
		print("Raycast hit: ", collider.name if collider else "null")
		print("  - Type: ", collider.get_class() if collider else "unknown")
		print("  - Parent: ", collider.get_parent().name if collider and collider.get_parent() else "no parent")
		print("  - Position: ", collision_point)
		print("  - Normal: ", collision_normal)
		print("  - Groups: ", collider.get_groups() if collider else [])
		
		if collider and collider.is_in_group("graffiti"):
			# Immediately hide the graffiti
			collider.visible = false
			
			# Also try to hide parent if collider is a collision shape
			if collider.get_parent():
				collider.get_parent().visible = false
			
			# Disable collision to prevent further hits
			if collider.has_method("set_disabled"):
				collider.set_disabled(true)
			
			# Remove the graffiti scene
			collider.queue_free()
			
			# Increment counter
			graffiti_counter += 1
			print("Graffiti cleaned! Total cleaned: ", graffiti_counter)
			
			# Switch to progress assistant when first graffiti is cleaned
			if graffiti_counter >= 1 and not has_switched_to_progress and not has_switched_to_eerie:
				switch_to_progress_assistant()
			
			# Hide graves when 6 graffiti are cleaned
			if graffiti_counter == 6 and not graves_hidden:
				hide_graves()
	else:
		print("Raycast not colliding with anything")


func get_graffiti_counter() -> int:
	"""Get the current graffiti counter value"""
	return graffiti_counter


func hide_graves():
	"""Hide the graves when 6 graffiti are cleaned"""
	var graves = get_node_or_null("/root/Main/Graves")
	if graves:
		graves.visible = false
		graves_hidden = true
		print("Graves hidden after cleaning 6 graffiti!")
		print("Car detection is now active!")
	else:
		print("Warning: Could not find /root/Main/Graves node")


func unhide_graffiti():
	"""Unhide all graffiti objects when car is detected"""
	# Find all nodes in the "graffiti" group and make them visible again
	var graffiti_nodes = get_tree().get_nodes_in_group("graffiti")
	var unhidden_count = 0
	
	for graffiti in graffiti_nodes:
		if graffiti and not graffiti.visible:
			graffiti.visible = true
			# Also make parent visible if it exists
			if graffiti.get_parent():
				graffiti.get_parent().visible = true
			unhidden_count += 1
	
	if unhidden_count > 0:
		print("Unhidden ", unhidden_count, " graffiti objects when car was detected!")
	else:
		print("No hidden graffiti found to unhide")


func check_car_in_view():
	"""Check if car is in view without raycast - detects even corner visibility"""
	if not graves_hidden:
		return  # Only check after graves are hidden
	
	if car_detected_after_graves:
		# After "uh oh" moment, check proximity for final sequence
		check_car_proximity()
		return  # Already detected initial view, only check proximity now
	
	# Try to find the car node
	var car = get_node_or_null("/root/Main/car")
	if not car:
		print("Warning: Could not find /root/Main/car node")
		return
	
	var car_position = car.global_position
	var camera_position = camera.global_position
	var direction_to_car = (car_position - camera_position).normalized()
	
	# Check if car is in the camera's view direction
	var camera_forward = -camera.global_transform.basis.z
	var dot_product = camera_forward.dot(direction_to_car)
	
	# Car is in view when dot product is above threshold (smaller FOV)
	# 0.5 means roughly 60-degree cone (30 degrees to each side)
	if dot_product > 0.5:
		print("Car detected in camera view! Dot product: ", dot_product)
		car_detected_after_graves = true
		print("uh oh")
		
		# Play violin sound
		if violin_audio_player and violin_audio_player.stream:
			violin_audio_player.play()
			print("Playing violin sound for car detection")
		
		# Unhide graffiti when car is detected
		unhide_graffiti()
		
		# Switch to eerie assistant after 0.5 seconds
		switch_to_eerie_assistant()
	else:
		# Only print debug occasionally to avoid spam
		if randf() < 0.01:  # 1% chance per frame
			print("Car not in view - Dot product: ", dot_product, " (need > 0.5)")

func check_car_proximity():
	"""Check if player is within 5 meters of car after uh oh moment"""
	if has_switched_to_fin:
		return  # Already switched to fin assistant
	
	# Try to find the car node
	var car = get_node_or_null("/root/Main/car")
	if not car:
		print("Warning: Could not find /root/Main/car node for proximity check")
		return
	
	var car_position = car.global_position
	var player_position = global_position
	var distance = car_position.distance_to(player_position)
	
	if distance <= 5.0:
		print("Player within 5 meters of car! Distance: ", distance)
		switch_to_fin_assistant()
	else:
		# Only print debug occasionally to avoid spam
		if randf() < 0.01:  # 1% chance per frame
			print("Distance to car: ", distance, " meters (need ≤ 5.0)")
