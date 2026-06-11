# Xbox button glyphs for prompts, plus the matching keyboard keycap
# style, so every "press X" in the game draws from one place. Pad
# players get sprites; keyboard players get styled keycaps.
class_name ButtonIcons

const TEX := {
	"a": preload("res://assets/xboxbuttons/Digital Buttons/ABXY/button_xbox_digital_a_1.png"),
	"b": preload("res://assets/xboxbuttons/Digital Buttons/ABXY/button_xbox_digital_b_1.png"),
	"x": preload("res://assets/xboxbuttons/Digital Buttons/ABXY/button_xbox_digital_x_1.png"),
	"y": preload("res://assets/xboxbuttons/Digital Buttons/ABXY/button_xbox_digital_y_1.png"),
	"start": preload("res://assets/xboxbuttons/Digital Buttons/System/button_xbox_digital_start_1.png"),
	"lb": preload("res://assets/xboxbuttons/Digital Buttons/Shoulder/button_xbox_digital_bumper_dark_1.png"),
	"rb": preload("res://assets/xboxbuttons/Digital Buttons/Shoulder/button_xbox_digital_bumper_dark_2.png"),
	"lt": preload("res://assets/xboxbuttons/Analog Triggers/button_xbox_analog_trigger_dark_1.png"),
	"rt": preload("res://assets/xboxbuttons/Analog Triggers/button_xbox_analog_trigger_dark_2.png"),
	"ls": preload("res://assets/xboxbuttons/Analog Sticks/Left/button_xbox_analog_l.png"),
}


static func icon(name: String, px := 34.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = TEX[name]
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


static func keycap(key_text: String) -> Label:
	var lbl := Label.new()
	lbl.text = key_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.96, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.18, 0.9)
	style.border_color = Color(0.5, 0.52, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	lbl.add_theme_stylebox_override("normal", style)
	return lbl
