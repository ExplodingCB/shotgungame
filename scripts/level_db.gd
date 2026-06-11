# Registry of versus arenas. Geometry lives in the level scenes; this
# table carries what other systems need without instancing: bounds,
# spawn points, rock density, and the scene path. Id 0 (Classic) is the
# solo arena and the warm-up lobby, and must always exist.
class_name LevelDB

const LEVELS := {
	0: {
		"scene_path": "res://levels/classic.tscn",
		"name": "Classic",
		"bounds": Rect2(-1600, -900, 3200, 1800),
		"spawns": [Vector2(-600, 0), Vector2(600, 0), Vector2(0, -450), Vector2(0, 450)],
		"asteroid_density": 1.0,
	},
	1: {
		"scene_path": "res://levels/cross.tscn",
		"name": "The Cross",
		"bounds": Rect2(-1600, -900, 3200, 1800),
		"spawns": [Vector2(-1350, 0), Vector2(1350, 0), Vector2(0, -700), Vector2(0, 700)],
		"asteroid_density": 0.4,
	},
	2: {
		"scene_path": "res://levels/donut.tscn",
		"name": "The Donut",
		"bounds": Rect2(-1600, -900, 3200, 1800),
		"spawns": [Vector2(-1300, -720), Vector2(1300, 720), Vector2(1300, -720), Vector2(-1300, 720)],
		"asteroid_density": 0.7,
	},
	3: {
		"scene_path": "res://levels/alley.tscn",
		"name": "Vortex Alley",
		"bounds": Rect2(-1800, -500, 3600, 1000),
		"spawns": [Vector2(-1650, -250), Vector2(1650, 250), Vector2(1650, -250), Vector2(-1650, 250)],
		"asteroid_density": 0.0,
	},
	4: {
		"scene_path": "res://levels/grinder.tscn",
		"name": "The Grinder",
		"bounds": Rect2(-1600, -900, 3200, 1800),
		"spawns": [Vector2(-1050, -450), Vector2(1050, 450), Vector2(1050, -450), Vector2(-1050, 450)],
		"asteroid_density": 0.4,
	},
	5: {
		"scene_path": "res://levels/pinball.tscn",
		"name": "Pinball",
		"bounds": Rect2(-1150, -700, 2300, 1400),
		"spawns": [Vector2(-950, -520), Vector2(950, 520), Vector2(950, -520), Vector2(-950, 520)],
		"asteroid_density": 0.0,
	},
	6: {
		"scene_path": "res://levels/binary.tscn",
		"name": "Binary Stars",
		"bounds": Rect2(-1600, -900, 3200, 1800),
		"spawns": [Vector2(-1300, -700), Vector2(1300, 700), Vector2(1300, -700), Vector2(-1300, 700)],
		"asteroid_density": 1.3,
	},
	7: {
		"scene_path": "res://levels/shoebox.tscn",
		"name": "Shoebox",
		"bounds": Rect2(-850, -550, 1700, 1100),
		"spawns": [Vector2(-650, -350), Vector2(650, 350), Vector2(650, -350), Vector2(-650, 350)],
		"asteroid_density": 0.0,
	},
}


# Random rotation that never repeats the level just played.
static func pick_next(current: int) -> int:
	var pool: Array = []
	for id in LEVELS:
		if id != current:
			pool.append(id)
	if pool.is_empty():
		return current
	return pool[randi() % pool.size()]
