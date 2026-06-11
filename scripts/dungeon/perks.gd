# Dungeon-run upgrades, all permanent for the run and all stacking.
# Two tiers: MAJORS come from Tech Cache rooms and boss spoils;
# MINORS are small field upgrades that ordinary room clears sometimes
# offer. AUX_RACK is the rare one-per-run prize that fits a second
# big-gun slot, slipped into either tier's offer at low odds.
# Player-side effects write the perk-hook vars on player.gd (neutral
# defaults outside dungeon runs); run-side effects (lifesteal,
# scavenging) live on the dungeon controller.
class_name DungeonPerks

enum Perk {
	HAIR_TRIGGER, HOT_LOADS, FLECHETTE, NANO_LEECH,
	REINFORCED, DAMPENERS, SCAVENGER, DEMOLITIONIST,
	M_CALIBRATION, M_FOCUS, M_PLATING, M_DEFLECTORS, M_SIPHON, M_PAYLOAD,
	AUX_RACK,
}

const MAJORS := [
	Perk.HAIR_TRIGGER, Perk.HOT_LOADS, Perk.FLECHETTE, Perk.NANO_LEECH,
	Perk.REINFORCED, Perk.DAMPENERS, Perk.SCAVENGER, Perk.DEMOLITIONIST,
]
const MINORS := [
	Perk.M_CALIBRATION, Perk.M_FOCUS, Perk.M_PLATING,
	Perk.M_DEFLECTORS, Perk.M_SIPHON, Perk.M_PAYLOAD,
]
const RACK_CHANCE := 0.12

const DATA := {
	Perk.HAIR_TRIGGER: {"name": "HAIR TRIGGER", "desc": "+30% fire rate"},
	Perk.HOT_LOADS: {"name": "HOT LOADS", "desc": "+35% damage"},
	Perk.FLECHETTE: {"name": "FLECHETTE SPLIT", "desc": "+2 projectiles per shot"},
	Perk.NANO_LEECH: {"name": "NANO LEECH", "desc": "kills repair +5 hull"},
	Perk.REINFORCED: {"name": "REINFORCED HULL", "desc": "+25 max hull, repaired now"},
	Perk.DAMPENERS: {"name": "KINETIC DAMPENERS", "desc": "-20% damage taken"},
	Perk.SCAVENGER: {"name": "SCAVENGER PROTOCOLS", "desc": "double supply drops"},
	Perk.DEMOLITIONIST: {"name": "DEMOLITIONIST", "desc": "+40% blast radius & damage"},
	Perk.M_CALIBRATION: {"name": "CALIBRATION", "desc": "+10% fire rate"},
	Perk.M_FOCUS: {"name": "FOCUS LENS", "desc": "+10% damage"},
	Perk.M_PLATING: {"name": "PLATING", "desc": "+10 max hull, repaired now"},
	Perk.M_DEFLECTORS: {"name": "DEFLECTORS", "desc": "-8% damage taken"},
	Perk.M_SIPHON: {"name": "SIPHON", "desc": "kills repair +2 hull"},
	Perk.M_PAYLOAD: {"name": "PAYLOAD", "desc": "+15% blast radius & damage"},
	Perk.AUX_RACK: {"name": "AUX RACK", "desc": "carry a second weapon\n(once per run)"},
}


static func apply(player: Node, run: Node, id: int) -> void:
	match id:
		Perk.HAIR_TRIGGER:
			player.fire_rate_mult *= 1.3
		Perk.HOT_LOADS:
			player.damage_mult *= 1.35
		Perk.FLECHETTE:
			player.extra_pellets += 2
		Perk.NANO_LEECH:
			run.lifesteal += 5.0
		Perk.REINFORCED:
			player.max_health += 25.0
			player.health = player.max_health
		Perk.DAMPENERS:
			player.incoming_mult *= 0.8
		Perk.SCAVENGER:
			run.scavenger_mult *= 2.0
		Perk.DEMOLITIONIST:
			player.explode_mult *= 1.4
		Perk.M_CALIBRATION:
			player.fire_rate_mult *= 1.1
		Perk.M_FOCUS:
			player.damage_mult *= 1.1
		Perk.M_PLATING:
			player.max_health += 10.0
			player.health = minf(player.health + 10.0, player.max_health)
		Perk.M_DEFLECTORS:
			player.incoming_mult *= 0.92
		Perk.M_SIPHON:
			run.lifesteal += 2.0
		Perk.M_PAYLOAD:
			player.explode_mult *= 1.15
		Perk.AUX_RACK:
			player.second_slot = true


static func roll(n: int, player: Node = null) -> Array:
	return _roll_from(MAJORS, n, player)


static func roll_minor(n: int, player: Node = null) -> Array:
	return _roll_from(MINORS, n, player)


static func _roll_from(tier: Array, n: int, player: Node) -> Array:
	var pool := tier.duplicate()
	pool.shuffle()
	var out: Array = pool.slice(0, n)
	if player != null and not bool(player.second_slot) and randf() < RACK_CHANCE:
		out[out.size() - 1] = Perk.AUX_RACK
	return out
