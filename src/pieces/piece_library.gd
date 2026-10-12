class_name PieceLibrary
extends Resource

@export var pieces: Array[PieceData] = []


func find_tag(tag: StringName) -> PieceData:
	for piece in pieces:
		if piece.has_tag(tag):
			return piece
	return null
