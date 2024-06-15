@tool
@icon("noise_generator.svg")
class_name NoiseGenerator
extends ChunkAwareGenerator2D
## Takes a Dictionary of thresholds and tiles to generate organic terrain with different tiles for different heights.
## @tutorial(Generators): https://benjatk.github.io/Gaea/#/generators/
## @tutorial(NoiseGenerator): https://benjatk.github.io/Gaea/#/generators/noise

@export var settings: NoiseGeneratorSettings

func generate(starting_grid: GaeaGrid = null) -> void:
	if Engine.is_editor_hint() and not editor_preview:
		push_warning("%s: Editor Preview is not enabled so nothing happened!" % name)
		return

	if not settings:
		push_error("%s doesn't have a settings resource" % name)
		return

	generation_started.emit()

	var time_now :int = Time.get_ticks_msec()

	settings.noise.seed = seed

	if starting_grid == null:
		erase()
	else:
		grid = starting_grid

	_set_grid()
	_apply_modifiers(settings.modifiers)

	if is_instance_valid(next_pass):
		next_pass.generate(grid)
		return

	var time_elapsed: int = Time.get_ticks_msec() - time_now
	if OS.is_debug_build():
		print("%s: Generating took %s seconds" % [name, float(time_elapsed) / 1000])

	replace_tiles()
	
	grid_updated.emit()
	generation_finished.emit()

func generate_chunk(chunk_position: Vector2i, starting_grid: GaeaGrid = null) -> void:
	if Engine.is_editor_hint() and not editor_preview:
		return

	if not settings:
		push_error("%s doesn't have a settings resource" % name)
		return

	if starting_grid == null:
		erase_chunk(chunk_position)
	else:
		grid = starting_grid

	_set_grid_chunk(chunk_position)
	_apply_modifiers_chunk(settings.modifiers, chunk_position)

	generated_chunks.append(chunk_position)

	if is_instance_valid(next_pass):
		if not next_pass is ChunkAwareGenerator2D:
			push_error("next_pass generator is not a ChunkAwareGenerator2D")
		else:
			next_pass.generate_chunk(chunk_position, grid)
			return

	chunk_updated.emit(chunk_position)
	chunk_generation_finished.emit(chunk_position)

func _set_grid() -> void:
	_set_grid_area(Rect2i(Vector2i.ZERO, Vector2i(settings.world_size)))

func _set_grid_chunk(chunk_position: Vector2i) -> void:
	_set_grid_area(Rect2i(
		chunk_position * chunk_size,
		chunk_size
	))

func _set_grid_area(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		if not settings.infinite:
			if x < 0 or x > settings.world_size.x:
				continue

		for y in range(rect.position.y, rect.end.y):
			if not settings.infinite:
				if y < 0 or y > settings.world_size.x:
					continue

			var noise = settings.noise.get_noise_2d(x, y)
			if settings.falloff_enabled and settings.falloff_map and not settings.infinite:
				noise = ((noise + 1) * settings.falloff_map.get_value(Vector2i(x, y))) - 1.0

			for tile_data in settings.tiles:
				## Check if the noise is within the threshold
				if noise >= tile_data.min and noise <= tile_data.max:
					grid.set_valuexy(x, y, tile_data.tile)
					break

func replace_tiles():
	var tile_types = {
		'DEEPWATER': get_tile_by_id(settings.tiles, 'TILE_DEEPWATER'),
		'WATER': get_tile_by_id(settings.tiles, 'TILE_WATER'),
		'SAND': get_tile_by_id(settings.tiles, 'TILE_SAND'),
		'GRASS': get_tile_by_id(settings.tiles, 'TILE_GRASS'),
		'MOUNTAIN': get_tile_by_id(settings.tiles, 'TILE_MOUNTAIN'),
		'SNOW': get_tile_by_id(settings.tiles, 'TILE_SNOW')
	}
	
	var connecting_tiles = get_tile_by_id(settings.tiles, 'CONNECTING_TILES')
	var connecting_tile_types = {
		'DEEPWATER_WATER': get_tile_by_id(connecting_tiles.tiles, 'TILE_DEEPWATER_WATER'),
		'WATER_SAND': get_tile_by_id(connecting_tiles.tiles, 'TILE_WATER_SAND'),
		'SAND_GRASS': get_tile_by_id(connecting_tiles.tiles, 'TILE_SAND_GRASS'),
		'GRASS_MOUNTAIN': get_tile_by_id(connecting_tiles.tiles, 'TILE_GRASS_MOUNTAIN'),
		'MOUNTAIN_SNOW': get_tile_by_id(connecting_tiles.tiles, 'TILE_MOUNTAIN_SNOW')
	}
	
	iterate_and_replace_tiles(tile_types, 'GRASS', tile_types.get('SNOW'), tile_types.get('MOUNTAIN'))
	iterate_and_replace_tiles(tile_types, 'SAND', tile_types.get('MOUNTAIN'), tile_types.get('GRASS'))
	iterate_and_replace_tiles(tile_types, 'WATER', tile_types.get('GRASS'), tile_types.get('SAND'))
	iterate_and_replace_tiles(tile_types, 'DEEPWATER', tile_types.get('SAND'), tile_types.get('WATER'))
	
	iterate_and_replace_tiles(tile_types, 'DEEPWATER', tile_types.get('WATER'), connecting_tile_types.get('DEEPWATER_WATER'), true)
	iterate_and_replace_tiles(tile_types, 'WATER', tile_types.get('SAND'), connecting_tile_types.get('WATER_SAND'), true)
	iterate_and_replace_tiles(tile_types, 'SAND', tile_types.get('GRASS'), connecting_tile_types.get('SAND_GRASS'), true)
	iterate_and_replace_tiles(tile_types, 'GRASS', tile_types.get('MOUNTAIN'), connecting_tile_types.get('GRASS_MOUNTAIN'), true)
	iterate_and_replace_tiles(tile_types, 'MOUNTAIN', tile_types.get('SNOW'), connecting_tile_types.get('MOUNTAIN_SNOW'), true)
	
func iterate_and_replace_tiles(tile_types: Dictionary, current_tile_type_str: String, adjacent_tile_type: Object, replacement_tile_type: Object, is_connecting_tile: bool = false):
	var grid_size = Vector2i(settings.world_size)
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var tile_position = Vector2i(x, y)
			for layer in range(grid.get_layer_count()):
				var current_tile = grid.get_value(tile_position, layer)
				var current_tile_type = get_tile_type(current_tile, tile_types)
				match current_tile_type:
					current_tile_type_str:
						replace_with_tile(tile_position, layer, adjacent_tile_type, replacement_tile_type, is_connecting_tile)

func replace_with_tile(tile_position: Vector2i, layer: int, adjacent_tile_type: Object, replacement_tile_type: Object, is_connecting_tile: bool = false):
	var adjacent_directions = is_adjacent_to_tile(tile_position, adjacent_tile_type)
	if adjacent_directions.size():
		if is_connecting_tile:
			replacement_tile_type = get_tile_for_direction(adjacent_directions, replacement_tile_type)
		grid.set_value(tile_position, replacement_tile_type, layer)

func get_tile_by_id(tiles_array: Array, tile_id: String) -> Object:
	for tile in tiles_array:
		if 'tile' in tile and tile.tile.id == tile_id:
			return tile.tile
		elif 'id' in tile and tile.id == tile_id:
			return tile
	return null

func get_tile_type(current_tile: Object, tile_types: Dictionary) -> String:
	for tile_type in tile_types.keys():
		for tile in tile_types[tile_type].tiles:
			if current_tile == tile:
				return tile_type
	return ''

func is_adjacent_to_tile(tile_position: Vector2i, adjacent_tile_type: Object) -> Array:
	var adjacent_positions = {
		Vector2(0, -1): tile_position + Vector2i(0, -1),  # Top
		Vector2(0, 1): tile_position + Vector2i(0, 1),  # Bottom
		Vector2(1, 0): tile_position + Vector2i(1, 0),  # Right
		Vector2(-1, 0): tile_position + Vector2i(-1, 0), # Left
		Vector2(1, -1): tile_position + Vector2i(1, -1),  # Top right
		Vector2(-1, -1): tile_position + Vector2i(-1, -1),  # Top left
		Vector2(1, 1): tile_position + Vector2i(1, 1),  # Bottom right
		Vector2(-1, 1): tile_position + Vector2i(-1, 1) # Bottom left
	}
	
	var adjacent_directions = []
	for direction in adjacent_positions.keys():
		var position = adjacent_positions[direction]
		if is_in_bounds(position):
			for i in range(grid.get_layer_count()):
				for tile in adjacent_tile_type.tiles:
					if grid.get_value(position, i) == tile:
						adjacent_directions.append(direction)
	return adjacent_directions

func is_in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < settings.world_size.x and position.y >= 0 and position.y < settings.world_size.y

func get_tile_for_direction(adjecent_directions: Array, replacement_tile_type: Object) -> Object:
	var is_N = false
	var is_S = false
	var is_E = false
	var is_W = false
	var is_NE = false
	var is_NW = false
	var is_SE = false
	var is_SW = false
	
	for i in range(adjecent_directions.size()):
		match adjecent_directions[i]:
			Vector2(0, -1):
				is_N = true
			Vector2(0, 1):
				is_S = true
			Vector2(1, 0):
				is_E = true
			Vector2(-1, 0):
				is_W = true
			Vector2(1, -1):
				is_NE = true
			Vector2(-1, -1):
				is_NW = true
			Vector2(1, 1):
				is_SE = true
			Vector2(-1, 1):
				is_SW = true
	
	var build_id = ''
	
	if is_N:
		build_id += 'N'
		is_NE = false
		is_NW = false
	if is_S:
		build_id += 'S'
		is_SE = false
		is_SW = false
	if is_E:
		build_id += 'E'
		is_NE = false
		is_SE = false
	if is_W:
		build_id += 'W'
		is_NW = false
		is_SW = false
	if is_NE:
		if not '-' in build_id:
			build_id += '-'
		build_id += 'NE'
	if is_NW:
		if not '-' in build_id:
			build_id += '-'
		build_id += 'NW'
	if is_SE:
		if not '-' in build_id:
			build_id += '-'
		build_id += 'SE'
	if is_SW:
		if not '-' in build_id:
			build_id += '-'
		build_id += 'SW'
	
	return get_tile_by_id(replacement_tile_type.tiles, build_id)
