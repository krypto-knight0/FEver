extends RefCounted
## Temporary mounted resources, never a persistent decoded-cartridge cache.
var directory := ""
var digest := ""
var error := ""
var generation := 0
var session_id := str(Time.get_ticks_usec())

func mount(resources: Dictionary) -> bool:
	generation += 1
	var base := directory+"/dynamic-"+digest+"-%d-%s-%d" % [OS.get_process_id(),session_id,generation]
	var packer := PCKPacker.new()
	var pack := base+".pck"
	if packer.pck_start(pack) != OK: error = "Cannot create dynamic chapter package."; return false
	var staged: Array[String] = []
	var ok := true
	for path in resources:
		var file_path := base+"-%d.json" % staged.size()
		staged.append(file_path)
		var file := FileAccess.open(file_path,FileAccess.WRITE)
		if file == null: ok = false; break
		file.store_string(JSON.stringify(resources[path],"",false)); file.flush()
		ok = file.get_error() == OK; file.close()
		if not ok or packer.add_file(path,file_path) != OK: ok = false; break
	if ok: ok = packer.flush() == OK
	for file_path in staged: DirAccess.remove_absolute(file_path)
	if ok: ok = ProjectSettings.load_resource_pack(pack,true)
	if not ok: error = "Cannot install dynamic chapter data."; DirAccess.remove_absolute(pack)
	return ok
