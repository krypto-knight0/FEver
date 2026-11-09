extends RefCounted
## Reads M4A note/control streams directly from the selected ROM.
const WAIT := [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,28,30,32,36,40,42,44,48,52,54,56,60,64,66,68,72,76,78,80,84,88,90,92,96]
const PARAMS := {0xba:"priority",0xbb:"tempo",0xbc:"transpose",0xbd:"voice",0xbe:"volume",0xbf:"pan",0xc0:"bend",0xc1:"bend_range",0xc2:"lfo_speed",0xc3:"lfo_delay",0xc4:"modulation",0xc5:"modulation_type",0xc8:"tune"}
const DEFAULTS := {"voice":0,"volume":100,"pan":64,"bend":64,"bend_range":2,"transpose":0,"lfo_speed":22,"lfo_delay":0,"modulation":0,"modulation_type":0,"tune":64}
var decoder: RefCounted
var tempos: Array = []

func track(offset: int) -> Dictionary:
	if decoder == null or not decoder.require_range(offset, 1, "Music track"): return {}
	var controls: Dictionary = {}
	for key in DEFAULTS: controls[key]=[[0,DEFAULTS[key]]]
	var result := {"notes":[],"controls":controls,"end":0,"loop":-1}
	var pc := offset
	var tick := 0
	var running := 0
	var key := 60
	var velocity := 100
	var voice := 0
	var transpose := 0
	var stack: Array = []
	var visited: Dictionary = {}
	var repeats: Dictionary = {}
	for iteration in range(100000):
		if tick > 30000: break
		if not visited.has(pc): visited[pc]=tick
		var command: int = decoder.rom[pc]
		if command >= 128:
			pc+=1
			if command>=0xbd: running=command
		elif running: command=running
		else: break
		if command>=0x80 and command<=0xb0: tick+=WAIT[command-0x80]
		elif command==0xb1: break
		elif command in [0xb2,0xb3]:
			var target: int = decoder.ptr(pc)
			pc+=4
			if command==0xb3:
				if stack.size()>=8: break
				stack.append(pc)
				pc=target
			elif visited.has(target):
				result.loop=visited[target]
				break
			else: pc=target
		elif command==0xb4:
			if not stack.is_empty(): pc=stack.pop_back()
		elif command==0xb5:
			var count: int = decoder.rom[pc]
			repeats[pc]=int(repeats.get(pc,0))+1
			if repeats[pc]<count: pc=decoder.ptr(pc+1)
			else:
				repeats[pc]=0
				pc+=5
		elif PARAMS.has(command):
			var value: int = decoder.rom[pc]
			pc+=1
			var parameter: String = PARAMS[command]
			if parameter=="tempo": value*=2
			elif parameter=="transpose":
				if value>127: value-=256
				transpose=value
			elif parameter=="voice": voice=value
			if not controls.has(parameter): controls[parameter]=[]
			controls[parameter].append([tick,value])
		elif command==0xcd: pc+=2
		elif command==0xce:
			var release_key := key
			if decoder.rom[pc]<128:
				release_key=decoder.rom[pc]
				pc+=1
			for note in result.notes:
				if note.end<0 and note.key==release_key+transpose: note.end=tick
		elif command>=0xcf:
			var length: int = -1 if command==0xcf else WAIT[command-0xcf]
			if decoder.rom[pc]<128:
				key=decoder.rom[pc]; pc+=1
				if decoder.rom[pc]<128:
					velocity=decoder.rom[pc]; pc+=1
					if decoder.rom[pc]<128:
						if length>=0: length+=int(decoder.rom[pc])
						pc+=1
			result.notes.append({"tick":tick,"end":-1 if length<0 else tick+length,"key":key+transpose,"velocity":velocity,"voice":voice})
		else: break
	result.end=tick
	for note in result.notes:
		if note.end<0:
			note.loop_sustain = result.loop >= 0 and int(note.tick) < int(result.loop)
			note.end=tick
	return result

func seconds(tick: int) -> float:
	var current: Array = tempos[0]
	for event in tempos:
		if int(event[0])>tick: break
		current=event
	return float(current[2])+(tick-int(current[0]))*60.0/maxf(1,float(current[1]))/24.0

func song(id: int) -> Dictionary:
	if decoder == null or not decoder.error.is_empty(): return {}
	var header: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("songs",0x3f50)))+id*8)
	if not decoder.require_range(header, 8, "Song header"): return {}
	var tracks: Array = []
	var tempo_values := {0:120}
	var end := 0
	var loop_tick := -1
	for i in range(decoder.rom[header]):
		var t := track(decoder.ptr(header+8+i*4))
		if not decoder.error.is_empty(): return {}
		tracks.append(t)
		for event in t.controls.get("tempo",[]): tempo_values[event[0]]=event[1]
		end=maxi(end,int(t.end))
		if t.loop>=0: loop_tick=int(t.loop) if loop_tick<0 else mini(loop_tick,int(t.loop))
	var ticks: Array = tempo_values.keys()
	ticks.sort()
	tempos=[]
	var elapsed := 0.0
	for i in range(ticks.size()):
		if i>0: elapsed+=(int(ticks[i])-int(ticks[i-1]))*60.0/float(tempo_values[ticks[i-1]])/24.0
		tempos.append([ticks[i],tempo_values[ticks[i]],elapsed])
	var notes: Array = []
	for t in tracks:
		for control in t.controls.values():
			for event in control: event[0]=seconds(int(event[0]))
		for n in t.notes:
			n.start=seconds(int(n.tick))
			n.finish=seconds(int(n.end))
			n.controls=t.controls
			notes.append(n)
	notes.sort_custom(func(a,b): return float(a.start)<float(b.start))
	return {"notes":notes,"voices":decoder.ptr(header+4),"duration":seconds(end),"loop":seconds(loop_tick) if loop_tick>=0 else -1.0}
