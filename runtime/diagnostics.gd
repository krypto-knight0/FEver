extends Node
## Durable, bounded breadcrumbs survive process kills as well as script errors.
const DIRECTORY := "user://diagnostics"
const LIMIT := 2 * 1024 * 1024
const TRACE_LIMIT := 8 * 1024 * 1024
const TRACE_COUNT := 4
var sink: Journal
var elapsed := 0.0
var context: Dictionary = {}

class Journal extends Logger:
	var lock := Mutex.new()
	var output: FileAccess
	func write(kind: String, details: Dictionary = {}) -> void:
		lock.lock()
		if output:
			if output.get_position() > 2 * 1024 * 1024:
				output.close()
				DirAccess.remove_absolute("user://diagnostics/session-older.jsonl")
				DirAccess.rename_absolute("user://diagnostics/session.jsonl", "user://diagnostics/session-older.jsonl")
				output = FileAccess.open("user://diagnostics/session.jsonl", FileAccess.WRITE)
			if output:
				output.store_line(JSON.stringify({"time": Time.get_datetime_string_from_system(true), "ticks_ms": Time.get_ticks_msec(), "event": kind, "details": details}))
				output.flush()
		lock.unlock()
	func _log_message(message: String, error: bool) -> void:
		write("stderr" if error else "stdout", {"message": message.left(4096)})
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		write("error", {"function": function, "file": file, "line": line, "code": code, "message": rationale.left(4096), "type": error_type})

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var unclean := FileAccess.file_exists(DIRECTORY + "/running")
	DirAccess.remove_absolute(DIRECTORY + "/previous.jsonl")
	DirAccess.rename_absolute(DIRECTORY + "/session.jsonl", DIRECTORY + "/previous.jsonl")
	sink = Journal.new()
	sink.output = FileAccess.open(DIRECTORY + "/session.jsonl", FileAccess.WRITE)
	OS.add_logger(sink)
	var marker := FileAccess.open(DIRECTORY + "/running", FileAccess.WRITE)
	if marker: marker.store_string("running"); marker.close()
	record("startup", {"pid":OS.get_process_id(), "previous_unclean_exit": unclean, "os": OS.get_name(), "version": OS.get_version(), "model": OS.get_model_name(), "engine": Engine.get_version_info().string, "app_name": ProjectSettings.get_setting("application/config/name", "FEver"), "app_version": ProjectSettings.get_setting("application/config/version", "unknown"), "renderer": RenderingServer.get_video_adapter_name()})
	_android_exit_history.call_deferred()

func _android_exit_history() -> void:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"): return
	var java = Engine.get_singleton("JavaClassWrapper")
	var version = java.wrap("android.os.Build$VERSION")
	if version == null or int(version.SDK_INT) < 30: return
	var runtime = Engine.get_singleton("AndroidRuntime")
	var application = runtime.getApplicationContext()
	if application == null: return
	var manager = application.getSystemService("activity")
	if manager == null: return
	var history = manager.getHistoricalProcessExitReasons(application.getPackageName(), 0, 4)
	var exception = java.get_exception()
	if exception != null:
		record("android_exit_history_unavailable", {"exception": str(exception.toString())})
		return
	if history == null: return
	var entries = history.toArray()
	if entries == null: return
	var activity_manager = java.wrap("android.app.ActivityManager")
	var low_memory_supported = activity_manager.isLowMemoryKillReportSupported()
	var support_error := _java_error(java)
	record("android_exit_history", {"count": entries.size(), "low_memory_kill_report_supported":low_memory_supported if support_error.is_empty() else null})
	for entry in entries:
		record("android_process_exit", {"pid":entry.getPid(), "timestamp_ms": entry.getTimestamp(), "reason": entry.getReason(), "status": entry.getStatus(), "description": entry.getDescription(), "pss_kib": entry.getPss(), "rss_kib": entry.getRss(), "importance": entry.getImportance()})
		# Android 12+ exposes native tombstones as binary protobufs, not text.
		if int(version.SDK_INT) >= 31 and int(entry.getReason()) == 5:
			_capture_native_trace(java, entry)
	_prune_native_traces()

func _trace_names() -> Array[String]:
	var names: Array[String] = []
	for filename in DirAccess.get_files_at(DIRECTORY):
		if filename.begins_with("native-crash-") and filename.ends_with(".pb") and filename.trim_prefix("native-crash-").trim_suffix(".pb").is_valid_int():
			names.append(filename)
	names.sort()
	return names

func _prune_native_traces() -> void:
	var names := _trace_names()
	while names.size() > TRACE_COUNT:
		DirAccess.remove_absolute(DIRECTORY + "/" + names.pop_front())

func _java_error(java) -> String:
	var exception = java.get_exception()
	return "" if exception == null else str(exception.toString()).left(1024)

func _capture_native_trace(java, entry) -> void:
	var timestamp := int(entry.getTimestamp())
	var filename := "native-crash-%d.pb" % timestamp
	var path := DIRECTORY + "/" + filename
	if FileAccess.file_exists(path): return
	record("native_crash_dump_begin", {"timestamp_ms": timestamp})
	var stream = entry.getTraceInputStream()
	var failure := _java_error(java)
	if stream == null or not failure.is_empty():
		if stream != null:
			stream.close()
			_java_error(java)
		record("native_crash_dump_unavailable", {"timestamp_ms": timestamp, "error": failure, "reason": "Android may have expired the trace."})
		return
	failure = _copy_native_trace(java, stream, path)
	if failure.is_empty():
		var saved := FileAccess.open(path, FileAccess.READ)
		record("native_crash_dump_saved", {"timestamp_ms": timestamp, "file": filename, "bytes": saved.get_length() if saved else 0})
	else:
		record("native_crash_dump_unavailable", {"timestamp_ms": timestamp, "error": failure})

func _copy_native_trace(java, stream, path: String) -> String:
	# Keep bytes in Java: ByteBuffer.array() may select its Object-returning
	# bridge method through JNI, yielding a JavaObject instead of PackedByteArray.
	var channels = java.wrap("java.nio.channels.Channels")
	var files = java.wrap("java.io.FileOutputStream")
	var source = channels.newChannel(stream)
	var failure := _java_error(java)
	var destination = null
	var target = null
	if failure.is_empty() and source != null:
		destination = files.FileOutputStream(ProjectSettings.globalize_path(path + ".partial"))
		failure = _java_error(java)
		if failure.is_empty() and destination != null:
			target = destination.getChannel()
			failure = _java_error(java)
	if failure.is_empty() and target == null: failure = "Cannot create crash dump file channel."
	var total := 0
	while failure.is_empty():
		# One extra byte distinguishes an exact-limit dump from an oversized one.
		var requested := mini(65536, TRACE_LIMIT + 1 - total)
		var count = target.transferFrom(source, total, requested)
		failure = _java_error(java)
		if not failure.is_empty(): break
		if not count is int or count < 0 or count > requested:
			failure = "Crash dump transfer returned an invalid size."
			break
		if count == 0: break
		total += count
		if total > TRACE_LIMIT:
			failure = "Crash dump exceeds the 8 MiB limit."
			break
	if failure.is_empty():
		target.force(false)
		failure = _java_error(java)
	if destination != null:
		destination.close()
		var close_error := _java_error(java)
		if failure.is_empty(): failure = close_error
	if source != null: source.close()
	else: stream.close()
	var source_close_error := _java_error(java)
	if failure.is_empty(): failure = source_close_error
	if failure.is_empty() and total == 0: failure = "Android returned an empty crash dump."
	if failure.is_empty():
		var saved := FileAccess.open(path + ".partial", FileAccess.READ)
		if saved == null or saved.get_length() != total: failure = "Crash dump file size does not match transferred bytes."
		if saved: saved.close()
	if failure.is_empty() and DirAccess.rename_absolute(path + ".partial", path) != OK:
		failure = "Cannot finish crash dump."
	if not failure.is_empty(): DirAccess.remove_absolute(path + ".partial")
	return failure

func set_context(value: Dictionary) -> void:
	context = value.duplicate()

func record(kind: String, details: Dictionary = {}) -> void:
	if sink: sink.write(kind, details)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 15: return
	elapsed = 0
	record_memory()

func record_memory(reason: String = "periodic") -> void:
	var resident: Dictionary = {}
	if OS.get_name() == "Android":
		var status := FileAccess.open("/proc/self/status", FileAccess.READ)
		if status:
			# procfs reports a zero file size; get_as_text() can return no data.
			# Read until EOF instead of trusting the virtual file's length.
			while not status.eof_reached():
				var line := status.get_line()
				if line.begins_with("VmRSS:") or line.begins_with("VmHWM:"): resident[line.get_slice(":", 0)] = line.get_slice(":", 1).strip_edges()
	record("memory", {"reason":reason, "static_bytes": OS.get_static_memory_usage(), "peak_static_bytes":OS.get_static_memory_peak_usage(), "system": OS.get_memory_info(), "resident": resident, "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "context": context})

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_OS_MEMORY_WARNING, NOTIFICATION_WM_CLOSE_REQUEST]: record("lifecycle", {"notification": what})
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_OS_MEMORY_WARNING]: record_memory("lifecycle_%d" % what)

func _exit_tree() -> void:
	record("shutdown")
	DirAccess.remove_absolute(DIRECTORY + "/running")
	if sink: OS.remove_logger(sink)

func export_to(path: String) -> String:
	record("export")
	var zip := ZIPPacker.new()
	if zip.open(path) != OK: return "Cannot write diagnostics to this location."
	sink.lock.lock()
	for filename in ["session.jsonl", "previous.jsonl", "session-older.jsonl"]:
		if not FileAccess.file_exists(DIRECTORY + "/" + filename): continue
		zip.start_file(filename)
		zip.write_file(FileAccess.get_file_as_bytes(DIRECTORY + "/" + filename))
		zip.close_file()
	sink.lock.unlock()
	for filename in _trace_names():
		var trace := FileAccess.open(DIRECTORY + "/" + filename, FileAccess.READ)
		if trace == null or trace.get_length() > TRACE_LIMIT: continue
		var error := zip.start_file("native-crashes/" + filename)
		while error == OK and trace.get_position() < trace.get_length():
			var chunk := trace.get_buffer(65536)
			if chunk.is_empty():
				error = ERR_FILE_CANT_READ
				break
			error = zip.write_file(chunk)
		if error == OK: error = zip.close_file()
		if error != OK:
			zip.close()
			return "Could not include native crash dumps."
	return "Diagnostics saved." if zip.close() == OK else "Could not finish diagnostics archive."

func show_export(parent: Node) -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.use_native_dialog = true
	picker.filters = PackedStringArray(["*.zip ; Diagnostics archive"])
	picker.current_file = "fever-diagnostics.zip"
	parent.add_child(picker)
	picker.file_selected.connect(func(path): export_to(path); picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)
