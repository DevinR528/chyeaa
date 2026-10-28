class_name PieceWriter
extends RefCounted
## Packs a piece scene and its PieceData. The in-game editor writes res:// files
## and upserts the loaded library. Tests pass user:// paths and no library.

const SCENE_DIR := "res://scenes/pieces"
const RESOURCE_DIR := "res://resources/pieces"


static func import_should_keep(existing: PieceData) -> bool:
	return existing != null and existing.authored_in_editor


static func id_ok(id: String) -> bool:
	if id.is_empty():
		return false
	for index in id.length():
		var code := id.unicode_at(index)
		var letter := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not letter and not digit and code != 95:
			return false
	return true


## Empty string on success. `library` is updated and saved when it has a path.
static func save_to(board: PieceBoard, scene_path: String, resource_path: String, library: PieceLibrary = null) -> String:
	if board == null or board.root == null:
		return "Nothing to save"
	var id := String(board.piece_id)
	if not id_ok(id):
		return "Piece id must be lowercase letters, numbers, and underscores"
	if library != null and _collides(library, board):
		return "That id is already in the library"
	var data := board.to_piece_data()
	if data.scene == null:
		return "Could not pack the piece"
	if ResourceSaver.save(data.scene, scene_path) != OK:
		return "Could not save the scene"
	data.scene = load(scene_path) as PackedScene
	if data.scene == null:
		return "Saved scene did not load"
	if ResourceSaver.save(data, resource_path) != OK:
		return "Could not save the piece"
	board.opened_id = board.piece_id
	if library == null:
		return ""
	var saved := load(resource_path) as PieceData
	if saved == null:
		return "Saved piece did not load"
	_upsert(library, saved)
	if library.resource_path.is_empty():
		return ""
	if ResourceSaver.save(library, library.resource_path) != OK:
		return "Could not save the library"
	return ""


static func save_editor_piece(board: PieceBoard, library: PieceLibrary) -> String:
	var id := String(board.piece_id)
	return save_to(
		board,
		SCENE_DIR.path_join(id + ".tscn"),
		RESOURCE_DIR.path_join(id + ".tres"),
		library,
	)


static func _collides(library: PieceLibrary, board: PieceBoard) -> bool:
	if board.piece_id == board.opened_id and board.opened_id != &"":
		return false
	for piece in library.pieces:
		if piece.piece_id == board.piece_id:
			return true
	return false


static func _upsert(library: PieceLibrary, data: PieceData) -> void:
	for index in library.pieces.size():
		if library.pieces[index].piece_id == data.piece_id:
			library.pieces[index] = data
			return
	library.pieces.append(data)
