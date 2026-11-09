extends RefCounted
## Stage both parts of a character pack before changing either active selection.
## Called on the import worker. Texture reloads remain on the main thread.
const Dialogue = preload("res://runtime/custom_portraits.gd")
const Cards = preload("res://runtime/custom_card_portraits.gd")
static var report = preload("res://runtime/import_report.gd").new()

static func import_pack(path: String) -> String:
	report = preload("res://runtime/import_report.gd").new()
	# A fresh directory also protects edited defaults when reimporting the same
	# ZIP fails partway through. Neither live pack is overwritten during staging.
	var id := (path + str(Time.get_ticks_usec()) + Crypto.new().generate_random_bytes(16).hex_encode()).sha256_text()
	var stores := [Dialogue.store, Cards.store]
	var fields := ["image", "card"]
	var selected: Array = []
	for index in range(stores.size()):
		var store = stores[index]
		var failure: String = store.import_pack(path, false, fields[index], false, id)
		report.accepted += store.report.accepted
		for warning in store.report.warnings: report.skip(fields[index] + ": " + warning)
		if not failure.is_empty():
			_discard(stores, id)
			return failure
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.root + id + "/portraits.json"))
		# An image-only legacy pack leaves existing cards alone, and vice versa.
		if not config.portraits.is_empty(): selected.append(store)
	if selected.is_empty():
		_discard(stores, id)
		return report.no_valid("character artwork")
	var backups: Array = []
	for store in selected:
		var active: String = store.root + "active.cfg"
		backups.append(FileAccess.get_file_as_string(active) if FileAccess.file_exists(active) else "")
	for index in range(selected.size()):
		var failure: String = selected[index].activate_pack(id)
		if failure.is_empty(): continue
		var restored := true
		for previous in range(index):
			if not _restore(selected[previous].root, backups[previous]): restored = false
		if restored: _discard(stores, id)
		return failure if restored else failure + " Could not restore the previous portrait selection."
	return ""

static func _restore(root: String, contents: String) -> bool:
	if contents.is_empty(): return DirAccess.remove_absolute(root + "active.cfg") == OK
	var file := FileAccess.open(root + "active.rollback", FileAccess.WRITE)
	if file == null: return false
	file.store_string(contents)
	file.flush()
	var failure := file.get_error()
	file.close()
	return failure == OK and DirAccess.rename_absolute(root + "active.rollback", root + "active.cfg") == OK

static func _discard(stores: Array, id: String) -> void:
	# Only this import's generated flat staging directories are eligible.
	for store in stores:
		var directory: String = store.root + id + "/"
		if not DirAccess.dir_exists_absolute(directory): continue
		for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory + file)
		DirAccess.remove_absolute(directory)
