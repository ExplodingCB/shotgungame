# Finds the gameplay scene a node lives in: the nearest ancestor in
# the "arena" group (Main and the dungeon root tag themselves).
# Spawning through this instead of get_tree().current_scene keeps fx
# and projectiles in their own world when a match runs embedded — the
# main menu plays a demo brawl inside a SubViewport, where
# current_scene is the menu, not the match.
class_name Arena


static func of(node: Node) -> Node:
	var n: Node = node
	while n != null and not n.is_in_group("arena"):
		n = n.get_parent()
	return n if n != null else node.get_tree().current_scene
