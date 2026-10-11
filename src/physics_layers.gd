class_name PhysicsLayers
extends RefCounted
## 2D collision layer bits. Names match `layer_names/2d_physics` in project.godot.

## Blocks bodies: terrain, solid grapple tiles, solid props, idle throwables, and
## the out-of-bounds walls.
const WORLD := 1 << 0
## Restarts the room on touch: death tiles.
const HAZARD := 1 << 1
const EXIT := 1 << 2
## The kill plane below the room.
const FALL := 1 << 3
## The player's body. Nothing collides with it; it keeps the player out of WORLD,
## where sensors and actors would treat it as terrain.
const PLAYER := 1 << 4
## ContactBox areas: stomps, hurts, and throwable hits between bodies.
const CONTACT := 1 << 5
## Sensor squares on grapple tiles. Mask 0, so bodies pass through; point queries find them.
const GRAPPLE := 1 << 6
## Sensor squares on pogo tiles. Mask 0, same as grapple.
const POGO := 1 << 7
