extends RefCounted
## Imported packs occupy subdirectories; root preference files are retained UI settings.
static func pack_bytes(root: String) -> int:
	if not DirAccess.dir_exists_absolute(root): return 0
	var total := 0
	for directory in DirAccess.get_directories_at(root):
		total += directory_bytes(root.path_join(directory))
	return total

static func directory_bytes(path: String) -> int:
	var directory := DirAccess.open(path)
	if directory == null: return 0
	var total := 0
	for name in directory.get_files():
		var file := FileAccess.open(path.path_join(name), FileAccess.READ)
		if file: total += file.get_length(); file.close()
	for name in directory.get_directories(): total += directory_bytes(path.path_join(name))
	return total

static func label(bytes: int) -> String:
	if bytes <= 0: return "0 MB"
	var megabytes := float(bytes) / 1048576.0
	return "%d MB" % roundi(megabytes) if megabytes >= 10 else "%.1f MB" % maxf(0.1, megabytes)
