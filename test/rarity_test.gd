# Headless check of the rarity table: 20k rolls must roughly match the
# configured weights, never produce a no-drop weapon, and reach every
# droppable weapon at least once. Run with:
#   godot --headless --path . -s res://test/rarity_test.gd
extends SceneTree

const ROLLS := 20000
const TOLERANCE := 0.25  # fraction of expected count


func _initialize() -> void:
	var failed := false
	var per_rarity := {}
	var per_weapon := {}
	for i in ROLLS:
		var id := WeaponDB.roll_weapon()
		if WeaponDB.DATA[id].get("no_drop", false):
			push_error("FAIL: rolled no-drop weapon %s" % WeaponDB.DATA[id]["name"])
			failed = true
		per_rarity[WeaponDB.rarity_of(id)] = per_rarity.get(WeaponDB.rarity_of(id), 0) + 1
		per_weapon[id] = per_weapon.get(id, 0) + 1

	var total_weight := 0
	for w in WeaponDB.RARITY_WEIGHTS.values():
		total_weight += w
	for r in WeaponDB.RARITY_WEIGHTS:
		var expected := ROLLS * float(WeaponDB.RARITY_WEIGHTS[r]) / total_weight
		var got: int = per_rarity.get(r, 0)
		print("%-10s expected ~%d got %d" % [WeaponDB.RARITY_NAMES[r], int(expected), got])
		if absf(got - expected) > expected * TOLERANCE:
			push_error("FAIL: %s spawn rate off (expected ~%d, got %d)"
					% [WeaponDB.RARITY_NAMES[r], int(expected), got])
			failed = true

	for id in WeaponDB.DATA:
		if WeaponDB.DATA[id].get("no_drop", false):
			continue
		if not per_weapon.has(id):
			push_error("FAIL: %s never dropped in %d rolls" % [WeaponDB.DATA[id]["name"], ROLLS])
			failed = true

	print("RARITY TEST FAILED" if failed else "RARITY TEST OK")
	quit(1 if failed else 0)
