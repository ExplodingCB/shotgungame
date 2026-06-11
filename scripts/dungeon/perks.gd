# Dungeon-run perks: permanent (for the run) modifiers handed out by
# Tech Cache rooms and boss spoils. Every perk can be taken more than
# once and stacks. Player-side effects write the perk-hook vars on
# player.gd (neutral 1.0/0 defaults outside dungeon runs); run-side
# effects (lifesteal, scavenging) live on the dungeon controller.
class_name DungeonPerks

enum Perk {
	HAIR_TRIGGER, HOT_LOADS, FLECHETTE, NANO_LEECH,
	REINFORCED, DAMPENERS, SCAVENGER, DEMOLITIONIST,
}

const DATA := {
	Perk.HAIR_TRIGGER: {
		"name": "HAIR TRIGGER",
		"desc": "+30% fire rate",
	},
	Perk.HOT_LOADS: {
		"name": "HOT LOADS",
		"desc": "+35% damage",
	},
	Perk.FLECHETTE: {
		"name": "FLECHETTE SPLIT",
		"desc": "+2 projectiles per shot",
	},
	Perk.NANO_LEECH: {
		"name": "NANO LEECH",
		"desc": "kills repair +5 hull",
	},
	Perk.REINFORCED: {
		"name": "REINFORCED HULL",
		"desc": "+25 max hull, repaired now",
	},
	Perk.DAMPENERS: {
		"name": "KINETIC DAMPENERS",
		"desc": "-20% damage taken",
	},
	Perk.SCAVENGER: {
		"name": "SCAVENGER PROTOCOLS",
		"desc": "double supply drops",
	},
	Perk.DEMOLITIONIST: {
		"name": "DEMOLITIONIST",
		"desc": "+40% blast radius & damage",
	},
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


# n distinct perks for a pick-one choice card row.
static func roll(n: int) -> Array:
	var pool: Array = DATA.keys()
	pool.shuffle()
	return pool.slice(0, n)
