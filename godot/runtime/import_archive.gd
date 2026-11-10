extends RefCounted
## Validates ordinary single-disk ZIPs before ZIPReader can allocate member data.
## Stores and Deflate are supported; encrypted, ZIP64 and ambiguous entries fail.
const END_SIGNATURE := 0x06054b50
const CENTRAL_SIGNATURE := 0x02014b50
const LOCAL_SIGNATURE := 0x04034b50
const DESCRIPTOR_SIGNATURE := 0x08074b50
const ZIP64_SENTINEL := 0xffffffff
const MAX_NAME_BYTES := 1024

var sizes: Dictionary = {}
var error := ""
var _names: Dictionary = {}
var _reader: ZIPReader
var _maximum_member_bytes := 0
var _allow_large_members := false

static func safe_path(path: String, allow_directory: bool = false) -> bool:
	if allow_directory and path.ends_with("/"):
		path = path.trim_suffix("/")
	if path.is_empty() or path.begins_with("/") or path.to_utf8_buffer().size() > MAX_NAME_BYTES:
		return false
	for character in path:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127 or character in "\\:<>\"|?*":
			return false
	for component in path.split("/"):
		if component in ["", ".", ".."] or component.ends_with(".") or component.ends_with(" "):
			return false
		var stem := component.get_slice(".", 0).to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL"]:
			return false
		if stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789¹²³":
			return false
	return true

func open_archive(path: String, maximum_archive_bytes: int, maximum_entries: int,
		maximum_member_bytes: int, maximum_total_bytes: int, allow_large_members: bool = false) -> String:
	close()
	error = ""
	sizes.clear()
	_names.clear()
	_maximum_member_bytes = maximum_member_bytes
	_allow_large_members = allow_large_members
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open the import ZIP.")
	var failure := _inspect(file, maximum_archive_bytes, maximum_entries, maximum_total_bytes)
	file.close()
	if not failure.is_empty():
		return _fail(failure)
	_reader = ZIPReader.new()
	if _reader.open(path) != OK:
		_reader = null
		return _fail("Cannot read the import ZIP.")
	# Require the same names/count as the validated directory. No alias lookup.
	var names := _reader.get_files()
	if names.size() != sizes.size():
		return _fail("ZIP directory does not match its entries.")
	for name in names:
		if not sizes.has(name):
			return _fail("ZIP contains an unsupported file name.")
		_names[str(name).to_lower()] = name
	return ""

func close() -> void:
	if _reader != null:
		_reader.close()
		_reader = null

func _fail(message: String) -> String:
	error = message
	close()
	sizes.clear()
	_names.clear()
	return error

func resolve_path(name: String) -> String:
	return str(_names.get(name.to_lower(), "")) if safe_path(name) else ""

func read_file(name: String, maximum_bytes: int = -1, recoverable: bool = false) -> PackedByteArray:
	if recoverable: error = ""
	if not error.is_empty():
		return PackedByteArray()
	var requested := name
	name = resolve_path(name)
	if _reader == null or not sizes.has(name) or name.ends_with("/"):
		_read_failure("Missing import file: " + requested, recoverable)
		return PackedByteArray()
	var limit := _maximum_member_bytes if maximum_bytes < 0 else mini(maximum_bytes, _maximum_member_bytes)
	var expected := int(sizes[name])
	if expected > limit:
		_read_failure("Import file exceeds its size limit: " + name, recoverable)
		return PackedByteArray()
	# ZIPReader bounds its output buffer by the central directory size and checks
	# decompression/CRC. The size check above must precede this call.
	var data := _reader.read_file(name, true)
	if data.size() != expected:
		_read_failure("Import file is corrupt or incomplete: " + name, recoverable)
		return PackedByteArray()
	return data

func _read_failure(message: String, recoverable: bool) -> void:
	if recoverable: error = message
	else: _fail(message)

func _inspect(file: FileAccess, maximum_archive_bytes: int, maximum_entries: int,
		maximum_total_bytes: int) -> String:
	var length := file.get_length()
	if length < 22:
		return "Invalid ZIP directory."
	if length > maximum_archive_bytes:
		@warning_ignore("integer_division") # Intentional integer truncation.
		return "Import ZIP exceeds the %d MiB archive limit." % (maximum_archive_bytes / 1048576)
	var tail_start := maxi(0, length - 65557)
	file.seek(tail_start)
	var tail := file.get_buffer(length - tail_start)
	var end := -1
	for at in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(at) == END_SIGNATURE and at + 22 + tail.decode_u16(at + 20) == tail.size():
			end = at
			break
	if end < 0:
		return "Invalid ZIP directory."
	var count := int(tail.decode_u16(end + 10))
	if tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0 or tail.decode_u16(end + 8) != count:
		return "Multipart ZIPs are not supported."
	if count == 65535: return "ZIP64 archives are not supported. Export a standard ZIP."
	if count < 1 or count > maximum_entries:
		return "This ZIP has %d entries. Use a ZIP with 1–%d files and folders." % [count, maximum_entries]
	var directory_size := int(tail.decode_u32(end + 12))
	var directory_start := int(tail.decode_u32(end + 16))
	var directory_end := tail_start + end
	if directory_size == ZIP64_SENTINEL or directory_start == ZIP64_SENTINEL or directory_start + directory_size != directory_end:
		return "Invalid or unsupported ZIP directory bounds."
	var offset := directory_start
	var total := 0
	var folded_names: Dictionary = {}
	var spans: Array = []
	for index in range(count):
		if offset + 46 > directory_end:
			return "Truncated ZIP entry."
		file.seek(offset)
		var header := file.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != CENTRAL_SIGNATURE:
			return "Invalid ZIP entry."
		var flags := int(header.decode_u16(8))
		var method := int(header.decode_u16(10))
		if flags & ~0x080e or method not in [0, 8]:
			return "Use an unencrypted ZIP with Store or Deflate compression."
		var name_length := int(header.decode_u16(28))
		var extra_length := int(header.decode_u16(30))
		var next := offset + 46 + name_length + extra_length + int(header.decode_u16(32))
		if name_length < 1 or name_length > MAX_NAME_BYTES or next > directory_end:
			return "Invalid ZIP file name or entry bounds."
		var name_bytes := file.get_buffer(name_length)
		if name_bytes.has(0):
			return "ZIP contains an unsafe or unsupported file name."
		var name := name_bytes.get_string_from_utf8()
		if name.to_utf8_buffer() != name_bytes or not safe_path(name, true):
			return "ZIP contains an unsafe or unsupported file name."
		if folded_names.has(name.to_lower()):
			return "ZIP contains duplicate or case-conflicting file names."
		folded_names[name.to_lower()] = name.ends_with("/")
		if not _supported_extra(file.get_buffer(extra_length)):
			return "Invalid ZIP extensions; ZIP64 and alternate file names are not supported."
		var compressed := int(header.decode_u32(20))
		var expanded := int(header.decode_u32(24))
		var local_offset := int(header.decode_u32(42))
		if header.decode_u16(34) != 0 or compressed == ZIP64_SENTINEL or expanded == ZIP64_SENTINEL or local_offset == ZIP64_SENTINEL:
			return "Multipart and ZIP64 entries are not supported."
		var file_kind := (int(header.decode_u32(38)) >> 16) & 0xf000
		if file_kind not in [0, 0x4000, 0x8000] or (file_kind == 0x4000 and not name.ends_with("/")):
			return "ZIP links and special files are not supported."
		if name.ends_with("/") and expanded != 0:
			return "ZIP folders must not contain file data."
		if method == 0 and compressed != expanded:
			return "Invalid stored ZIP entry size."
		if expanded == 0 and header.decode_u32(16) != 0:
			return "Invalid empty ZIP entry checksum."
		total += expanded
		# Partial importers can skip large members; read_file still enforces its
		# byte limit before allocating/decompressing any member.
		if expanded > _maximum_member_bytes and not _allow_large_members:
			@warning_ignore("integer_division") # Intentional integer truncation.
			return "Each import file must be no larger than %d MiB." % (_maximum_member_bytes / 1048576)
		if total > maximum_total_bytes:
			@warning_ignore("integer_division") # Intentional integer truncation.
			return "ZIP contents exceed the %d MiB expanded limit." % (maximum_total_bytes / 1048576)
		var failure := _inspect_local(file, header, name_bytes, directory_start, spans)
		if not failure.is_empty():
			return failure
		sizes[name] = expanded
		offset = next
	if offset != directory_end:
		return "ZIP entry count does not match its directory."
	# A file cannot also be a directory, including through a child's path.
	for name in folded_names:
		var parent: String = name.trim_suffix("/")
		if name.ends_with("/") and folded_names.has(parent):
			return "ZIP file and folder paths conflict."
		while parent.contains("/"):
			parent = parent.get_base_dir()
			if folded_names.has(parent):
				return "ZIP file and folder paths conflict."
	spans.sort_custom(func(a, b): return a[0] < b[0])
	var previous_end := 0
	for span in spans:
		if span[0] < previous_end:
			return "ZIP entries overlap."
		previous_end = span[1]
	return ""

func _inspect_local(file: FileAccess, central: PackedByteArray, name: PackedByteArray,
		directory_start: int, spans: Array) -> String:
	var offset := int(central.decode_u32(42))
	if offset + 30 > directory_start:
		return "Invalid ZIP file header bounds."
	file.seek(offset)
	var local := file.get_buffer(30)
	if local.size() != 30 or local.decode_u32(0) != LOCAL_SIGNATURE:
		return "Invalid ZIP file header."
	if local.decode_u16(6) != central.decode_u16(8) or local.decode_u16(8) != central.decode_u16(10):
		return "ZIP file headers disagree."
	var name_length := int(local.decode_u16(26))
	var extra_length := int(local.decode_u16(28))
	var data_start := offset + 30 + name_length + extra_length
	var data_end := data_start + int(central.decode_u32(20))
	if name_length != name.size() or data_end > directory_start:
		return "Invalid ZIP file data bounds."
	if file.get_buffer(name_length) != name or not _supported_extra(file.get_buffer(extra_length)):
		return "ZIP file headers disagree or use unsupported extensions."
	var descriptor := bool(local.decode_u16(6) & 8)
	for pair in [[14, 16], [18, 20], [22, 24]]:
		var value := local.decode_u32(pair[0])
		if value != central.decode_u32(pair[1]) and not (descriptor and value == 0):
			return "ZIP file sizes or checksums disagree."
	if descriptor:
		if data_end + 12 > directory_start:
			return "Truncated ZIP data descriptor."
		file.seek(data_end)
		var data := file.get_buffer(mini(16, directory_start - data_end))
		var prefix := 4 if data.decode_u32(0) == DESCRIPTOR_SIGNATURE else 0
		if data.size() < prefix + 12:
			return "Truncated ZIP data descriptor."
		for index in range(3):
			if data.decode_u32(prefix + index * 4) != central.decode_u32(16 + index * 4):
				return "ZIP data descriptor disagrees with its directory."
		data_end += prefix + 12
	spans.append([offset, data_end])
	return ""

static func _supported_extra(bytes: PackedByteArray) -> bool:
	var offset := 0
	while offset < bytes.size():
		if offset + 4 > bytes.size():
			return false
		var kind := bytes.decode_u16(offset)
		var length := int(bytes.decode_u16(offset + 2))
		if kind in [0x0001, 0x7075] or offset + 4 + length > bytes.size():
			return false
		offset += 4 + length
	return true
