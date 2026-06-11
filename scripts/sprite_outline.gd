# Flat-white silhouette textures for drawing outlines and halos behind
# sprites: same alpha as the source, every visible pixel white, so a
# tinted draw_texture_rect() gives a clean outline in any color.
# Cached per source texture — pickups respawn constantly.
class_name SpriteOutline

static var _cache := {}


static func silhouette(tex: Texture2D) -> Texture2D:
	var key := tex.get_rid()
	if _cache.has(key):
		return _cache[key]
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, img.get_pixel(x, y).a))
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out
