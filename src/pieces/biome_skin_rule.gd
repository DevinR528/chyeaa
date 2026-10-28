class_name BiomeSkinRule
extends Resource
## One kind cell a biome knows how to draw as an art tile.
## `neighbor_mask` is reserved for later autotile rules. -1 means ignore neighbors.

@export var kind := Room.Kind.SOLID
## -1 ignores neighbors. Any other value is stored for later and not matched yet.
@export var neighbor_mask := -1
## Layer on the generated room that receives the art tile. Empty BlockTerrain is
## the place for a tileset other than kind tiles.
@export var layer := &"Terrain"
@export var atlas := Vector2i.ZERO
