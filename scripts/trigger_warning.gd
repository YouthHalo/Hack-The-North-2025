extends ColorRect

@onready var rich_text_label: RichTextLabel = $RichTextLabel
var period_timer: float = 0.0
var fade_timer: float = 0.0
var periods_added: int = 0
var started_fade: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Start the period adding process
	period_timer = 0.0
	fade_timer = 0.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Add periods every 0.8 seconds
	period_timer += delta
	if period_timer >= 0.8:
		add_period()
		period_timer = 0.0
	
	# Start fade after 1 second (but only once)
	fade_timer += delta
	if fade_timer >= 1.0 and not started_fade:
		start_fade_to_main()
		started_fade = true

func add_period() -> void:
	if rich_text_label:
		var current_text = rich_text_label.text
		rich_text_label.text = current_text + "."
		periods_added += 1

func start_fade_to_main() -> void:
	# Create a fade transition
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(change_to_main_scene)

func change_to_main_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
