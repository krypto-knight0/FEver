extends Node
## Native mixer voices play original ROM samples. No reverb, filters, distortion
## or time scaling. PSG oscillators and frame-rate envelopes remain approximations.
var stream: AudioStream
var playing := false
var volume_db := 0.0
var pitch_scale := 1.0
var sequence: Dictionary = {}
var elapsed := 0.0
var next_note := 0
var voices: Array = []
var decoder: RefCounted
static var sample_cache: Dictionary = {}
static var sample_bytes := 0
static var song_cache: Dictionary = {}
static var cache_decoder: WeakRef

func _bind_cache() -> void:
	# Song IDs and sample addresses are local to one loaded ROM instance.
	if cache_decoder != null and cache_decoder.get_ref() == decoder: return
	song_cache.clear()
	sample_cache.clear()
	sample_bytes = 0
	cache_decoder = weakref(decoder)

func _ready() -> void:
	decoder=preload("res://runtime/rom_assets.gd").decoder
	for i in range(32):
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append({"player":player,"note":{},"level":0.0})

func play(from_position: float = 0.0) -> void:
	stop()
	if decoder == null or not decoder.error.is_empty(): return
	_bind_cache()
	if not stream or not stream.has_meta("rom_song"): return
	var id := int(stream.get_meta("rom_song"))
	if not song_cache.has(id):
		var parser := preload("res://runtime/m4a_sequence.gd").new()
		parser.decoder=decoder
		var song: Dictionary = parser.song(id)
		if not decoder.error.is_empty() or song.is_empty(): return
		song_cache[id] = song
	sequence=song_cache[id]
	elapsed=from_position
	next_note=0
	playing=true
	_process(0.0)

func stop() -> void:
	playing=false
	for voice in voices:
		voice.player.stop()
		voice.note={}

func get_playback_position() -> float: return elapsed

func control(note: Dictionary, control_name: String, time: float) -> float:
	var events: Array = note.controls.get(control_name,[[0,0]])
	var value := float(events[0][1])
	for event in events:
		if float(event[0])>time: break
		value=float(event[1])
	return value

func instrument(note: Dictionary) -> Array:
	var at := int(sequence.voices)+int(note.voice)*12
	var drum := false
	for i in range(4):
		var kind: int = decoder.rom[at]
		if kind==0x40: at=decoder.ptr(at+4)+int(decoder.rom[decoder.ptr(at+8)+int(note.key)])*12
		elif kind==0x80:
			at=decoder.ptr(at+4)+int(note.key)*12
			drum=true
		else: return [at,drum]
	return [at,drum]

func sample(at: int, pan: int) -> AudioStreamWAV:
	if decoder == null or not decoder.error.is_empty(): return null
	_bind_cache()
	var cache_key := str(at)+":"+str(pan)
	if sample_cache.has(cache_key): return sample_cache[cache_key]
	var kind: int = decoder.rom[at]&7
	var mono := PackedFloat32Array()
	var result := AudioStreamWAV.new()
	result.format=AudioStreamWAV.FORMAT_16_BITS
	result.stereo=true
	if kind==0:
		var address: int = decoder.ptr(at+4)
		var count: int = decoder.u32(address+12)
		if not decoder.error.is_empty(): return null
		mono.resize(count)
		for i in range(count): mono[i]=float(decoder.rom.decode_s8(address+16+i))/128.0
		result.mix_rate=roundi(float(decoder.u32(address+4))/1024.0)
		if decoder.u32(address)&0x40000000:
			result.loop_mode=AudioStreamWAV.LOOP_FORWARD
			result.loop_begin=decoder.u32(address+8)
			result.loop_end=count
	elif kind in [1,2,3]:
		mono.resize(32)
		for i in range(32):
			if kind==3:
				@warning_ignore("integer_division") # Intentional integer truncation.
				var byte: int = decoder.rom[decoder.ptr(at+4)+i/2]
				mono[i]=(float((byte>>(4 if i%2==0 else 0))&15)/7.5-1.0)*0.5
			else: mono[i]=0.5 if i<float([4,8,16,24][decoder.u32(at+4)&3]) else -0.5
		result.mix_rate=8372
		result.loop_mode=AudioStreamWAV.LOOP_FORWARD
		result.loop_end=32
	else:
		# Hardware-style deterministic LFSR noise, never an external sound file.
		mono.resize(32767)
		var lfsr := 32767
		for i in range(mono.size()):
			mono[i]=0.4 if lfsr&1 else -0.4
			lfsr=(lfsr>>1)|(((lfsr^(lfsr>>1))&1)<<14)
		result.mix_rate=22050
		result.loop_mode=AudioStreamWAV.LOOP_FORWARD
		result.loop_end=mono.size()
	var data := PackedByteArray()
	data.resize(mono.size()*4)
	var left := sqrt(1.0-pan/127.0)
	var right := sqrt(pan/127.0)
	for i in range(mono.size()):
		data.encode_s16(i*4,roundi(mono[i]*left*32767))
		data.encode_s16(i*4+2,roundi(mono[i]*right*32767))
	if result.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		# Godot 4.6's mixer wraps at loop_end but can also decode that index.
		# Keep the ROM's exclusive endpoint and supply its next (loop-start)
		# stereo frame. Reducing loop_end would shorten the loop/change pitch.
		# https://github.com/godotengine/godot/issues/119778
		var first := result.loop_begin * 4
		data.append_array(data.slice(first, first + 4))
	result.data=data
	# Bound retained sample variants; active voices retain their own references.
	while not sample_cache.is_empty() and (sample_cache.size() >= 192 or sample_bytes + data.size() > 16 * 1024 * 1024):
		var oldest: String = sample_cache.keys()[0]
		sample_bytes -= sample_cache[oldest].data.size()
		sample_cache.erase(oldest)
	sample_cache[cache_key]=result
	sample_bytes += data.size()
	return result

func _start(note: Dictionary) -> void:
	if decoder == null or not decoder.error.is_empty():
		stop()
		return
	var chosen: Dictionary = voices[0]
	for voice in voices:
		if voice.note.is_empty() or not voice.player.playing:
			chosen=voice
			break
		if float(voice.level)<float(chosen.level): chosen=voice
	var inst := instrument(note)
	var at := int(inst[0])
	var kind: int = decoder.rom[at]&7
	var pan := int(control(note,"pan",elapsed))
	if inst[1] and decoder.rom[at+3]&128: pan=clampi(pan+(int(decoder.rom[at+3])&127)-64,0,127)
	chosen.player.stop()
	chosen.note=note
	chosen.at=at
	chosen.key=int(decoder.rom[at+1]) if inst[1] else int(note.key)
	chosen.level=0.0
	chosen.kind=kind
	chosen.player.stream=sample(at,pan)
	if chosen.player.stream == null:
		stop()
		return
	_update_voice(chosen,1.0/60.0)
	chosen.player.play(maxf(0,elapsed-float(note.start)))

func _update_voice(voice: Dictionary, delta: float) -> void:
	var note: Dictionary = voice.note
	var at := int(voice.at)
	var adsr: PackedByteArray = decoder.raw(at+8,4)
	if adsr.size() != 4:
		stop()
		return
	var attack := int(adsr[0])
	var decay := int(adsr[1])
	var sustain := int(adsr[2])
	var release := int(adsr[3])
	if voice.kind!=0:
		@warning_ignore("integer_division") # Intentional integer truncation.
		attack=255 if attack==0 else maxi(1,255/attack)
		decay=230 if decay else 255
		sustain=mini(255,sustain*17)
		release=mini(250,220+release*3)
	var age := elapsed-float(note.start)
	if elapsed>=float(note.finish): voice.level*=pow(release/256.0,delta*60.0)
	elif age<float(ceil(255.0/maxi(1,attack)))/60.0: voice.level=minf(1.0,float(voice.level)+maxi(1,attack)/255.0*delta*60.0)
	else: voice.level=maxf(sustain/255.0,float(voice.level)*pow(decay/256.0,delta*60.0))
	if elapsed>float(note.finish)+2.0 or (elapsed>=float(note.finish) and voice.level<0.0001):
		voice.player.stop()
		voice.note={}
		return
	var gain := float(voice.level)*control(note,"volume",elapsed)/127.0*int(note.velocity)/127.0*0.24
	voice.player.volume_db=volume_db+linear_to_db(maxf(0.00001,gain))
	var bend := (control(note,"bend",elapsed)-64.0)/64.0*control(note,"bend_range",elapsed)
	var tune := (control(note,"tune",elapsed)-64.0)/64.0
	var modulation := 0.0
	if age>=control(note,"lfo_delay",elapsed)/60.0: modulation=sin(TAU*age*control(note,"lfo_speed",elapsed)*60.0/256.0)*control(note,"modulation",elapsed)/16.0
	voice.player.pitch_scale=1.0 if voice.kind==0 and decoder.rom[at]&8 else pow(2.0,(int(voice.key)-60.0+bend+tune+modulation)/12.0)

func _process(delta: float) -> void:
	if not playing: return
	if decoder == null or not decoder.error.is_empty():
		stop()
		return
	elapsed+=delta
	var looping: bool = stream.get_meta("rom_loop",false) and float(sequence.loop)>=0
	if elapsed>=float(sequence.duration) and looping:
		elapsed=float(sequence.loop)+fposmod(elapsed-float(sequence.loop),maxf(0.001,float(sequence.duration)-float(sequence.loop)))
		next_note=0
		for voice in voices:
			# TIE notes begun before the GOTO sustain across the loop (wind ambience).
			if voice.note.get("loop_sustain", false): continue
			voice.player.stop()
			voice.note={}
		while next_note<sequence.notes.size() and float(sequence.notes[next_note].start)<float(sequence.loop): next_note+=1
	while next_note<sequence.notes.size() and float(sequence.notes[next_note].start)<=elapsed:
		var note: Dictionary = sequence.notes[next_note]
		if float(note.finish)>elapsed: _start(note)
		if not playing: return
		next_note+=1
	for voice in voices:
		if not voice.note.is_empty(): _update_voice(voice,delta)
	if not looping and elapsed>float(sequence.duration)+2.0: stop()
