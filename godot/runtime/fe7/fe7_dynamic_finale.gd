extends RefCounted
## Reviewed final-chapter helpers. Native data remains in the cartridge.
const Pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const SPECS := {
	0x7febc:[144,[120, 121, 122, 123, 128, 129, 130, 131, 136, 137, 138, 139],"74adc90ac0123369d55a49a5613c0c472e8e38e07b36a69db87682571e27c7e4"],
	0x7c754:[136,[],"4600fe25a699d68a7fd22f7d75507afac87f09f528af2ac5544a2b2d37437043"],
	0x7c7dc:[12,[],"cd5787b08eb7f22eb7b4940e1f13e8bf9d8f5612a308e55d0ffc3e48c6c5beda"],
	0x7ca1c:[20,[],"f12e1989f82cec80d1f286bc2ff861f45673e0c999a975e878d2b288287432db"],
	0x8046c:[20,[],"9b5df736ac1db570694b447adf83185893dc5258a87e8bc2ace763ba8816236d"],
	0x80214:[20,[],"a4c33c3fd93909ae2d9e27c275dc00b026c3d856491b8bffb4a6cd4b2f9b9e2e"],
	0xf224:[12,[],"96c6ce280bdc1847bbf7ddbf2dda6a6a516ef7c566d4a2851de6817a280e85f1"],
	0x7b304:[40,[],"dbecaaee16b29da657edb2dc9aa98f1a4da8050866b3370bcb41be2c89e54241"],
	0x7b750:[40,[],"25b06d186fbd77a5fd0304ce1a4eda224ae111ded510f8c01337e20fe46824ac"],
	0x7b778:[40,[],"f2d0c1be8738bcae04a2e6dd19b9b24df254f8e5573b18feff665b3bd6c0b00a"],
	0x7b8a4:[40,[],"a7eb1ac3e08ca00e7fab547de58464e2591a9a37cd347f9de2125af1e5c8c731"],
	0x7c658:[20,[],"ebb0c3490408240df459c748cf0d6f536f1891bba0b25bdf90df263d819cb910"],
	0x7d314:[20,[],"cae80aa7eed73e2c9ab7e1ad1c756bbf8d8e6d138ec0719757b850ba56a30dfe"],
	0x7d96c:[16,[],"540d95be765f5e0b720d03b468ba0b6879097b1d7cfa492f090a8b42816d1473"],
	0x7e9a4:[32,[],"3224afe13838b7d5ed814c21138ef0c1e5556994d8e5087ec27e4388d19cb31d"],
	0x7e9c4:[28,[],"533d6d3e251717ef80f1013e326c273523c7b333d09b635d88c3622b4ef42b4d"],
	0x7ea0c:[312,[],"82d76a3f1a36ea8470e3f2f39d7220e02d11d4033c18c1b4282f3294b524f307"],
	0x7eb80:[28,[],"cfccaa42b4567b5a796a34f80a3467b1d71b6980d1896d8edf6d531eb36e049c"],
	0x7ebcc:[140,[132, 133, 134, 135],"16d10f7302c570aeb713092f9347787774ddcd65290e118cf30305b0342cbc05"],
	0x7ec58:[124,[36, 37, 38, 39],"ee63e8aaa7e2f545b72dc743c8b571d3d3a799af8a8097ab1ece893e0b34f8c2"],
	0x7ecd4:[184,[176, 177, 178, 179],"5c2987f1839529137416b6f137e914c4e45c102dfedf93ac146b67f5483297b8"],
	0x7ed8c:[168,[160, 161, 162, 163],"c0e969b0b07e23eed8969ba84797d3395be65d5f2ec6e3bb94837a3b1d3ba5ff"],
	0x7ee34:[164,[156, 157, 158, 159],"4b02a6affc8e519e992eba9bafbce0570e67a020d11fd1a51917392b1bedf64b"],
	0x7eed8:[132,[52, 53, 54, 55],"af514959e783c6c6db3f36aa895177daf5434360c62505382bbe2f21a7ba9fc5"],
	0x7ef5c:[12,[],"ae5f05f9d1c6e0464bf90e405e94ac01481aee71ef0557d3d6291c7abcadfbca"],
	0x7ef7c:[392,[128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155],"cb96400aae2f0619eb44fe3ad5cbde3dd53444431b9ce50ad20c427e8206bd0c"],
	0x7f104:[104,[92, 93, 94, 95],"3d7aa6c96de8fe54390fb35bc06112d0ce3dc50d9adcd0ec10f29e330fce2e18"],
	0x7f198:[32,[24, 25, 26, 27, 28, 29, 30, 31],"c55cdf888e9a33f7dc0be69c6305cce95cf3e31768a052ca0a0f52a875d1e7b3"],
	0x7f1b8:[36,[],"90d73cc127748d9aa226f34851919897312448de5e58aa36db356bb373b1bea7"],
	0x7f1dc:[32,[],"e222613a8e8fc65e02797acc3c614956e32fd2c730c6ac1f0975b04ee4241cf6"],
	0x7f438:[16,[],"2f1915940af761588a29681f7204be8311c6751f6bc5ee9861ab7b7c4e15f6f3"],
	0x7f5c8:[72,[],"a9bbc6aee1d3c63816e0f54e83d343e54470f4e43b68588f5b9951bfa4c359d9"],
	0x7f610:[28,[],"4acb784eabf44e394b5075b5e9c680a241650f7c723de5a29dca444f6dab1456"],
	0x7f62c:[28,[],"54803cf66e1e07ce863164ccd7982ff5cfdf92aec6d302810f305b5ceb0b60ca"],
	0x7f648:[72,[],"e15fb01b07548bef41f31a93edb2b9973d9d7418098ed2ae09b08ffcf9110e1c"],
	0x7f690:[32,[],"4b4897ad1c5160af891635eba6e2269f9127c9c11231818f46a32e40e6021458"],
	0x7f6b0:[32,[],"c33244c21e37167ae763eb21430843cb8393315c4f4fca8c0a9dfee8fdec33c7"],
	0x7f6d0:[72,[],"f6f1852ae49691fa87077bdb1c9ea146bcb67376f2033569c51146ad7d82c7a8"],
	0x7f718:[32,[],"b60a72b2da4013d70b9d0feff75b2d2694fdd8e6827366dd72f3cd1a299b6fd5"],
	0x7f738:[32,[],"41debbcde150d8b86ae54b5ba8d34b0ce51b650fab11881822359f6abd028447"],
	0x7f758:[52,[],"b75b75e79d3959e3d0f18702882b168bf5ad51996126cddb6df1f09bec90cbad"],
	0x7f78c:[48,[],"1fa656a54ba2546844948105c3a6ad63f7575c49284091d2aad17855782bed24"],
	0x7f7bc:[48,[],"1e31e3d7d84d2c120ab39a3d11aae7da09208a1906e479a528f31dd9ca4f19d3"],
	0x7f8f4:[20,[],"b6c363a894e2b28fc663c3def1218692e6b79b0475a0f4f8bf19359eafa97e69"],
	0x7f908:[16,[],"fa0cdda35280b83d4d0a6bb50950dfbbc43728804e323fd41d0485ab7128eeb6"],
	0x7f918:[64,[],"aa93815390efc40086129a2f200387c4c7828361d90a9191916f246d82cafe44"],
	0x7f958:[72,[],"ba343c7522878d9df001316f8090d3140927cf963b948c72f84521ba6e4e4765"],
	0x7f9a0:[48,[],"a9f981445a45bb19f68460ce94937e2c52d8e30c8b1e7b866a432abcc8434a8f"],
	0x7f9d0:[28,[],"b5692de1338ea4b4ad7e9595d448520fe6c190b26e752c7d0587968cab3b47a9"],
	0x7fae8:[20,[],"a0b275e549a6b93e1b48458d3a7ec26903b54c69ed31e92c7c4c2fee19f4019c"],
	0x7fafc:[56,[],"0c2c1a5016f5026c25dcc3c2c564ecc80630c443cc07970b4b01d0849119a461"],
	0x7fb34:[12,[],"8fd649133777a6ac12d5384bc3a1ba0681dc91d5a901476e7617953527501bd3"],
}

static func callback(d: RefCounted, at: int) -> Dictionary:
	var spec: Array = SPECS[at]
	if not Pure.signature(d,at,int(spec[0]),spec[1],spec[2]):
		d.fail("FE7 finale","Changed native final-chapter helper.",at); return {}
	return {"op":"fe7_finale","address":at}

static func commands(compiler, at: int, scene_chapter: int) -> Array:
	var d: RefCounted = compiler.d
	if at == 0x7febc:
		var path: String = compiler.data.prefix+"scenes/ending_stamp.png"
		compiler.data.assets[path] = {"kind":"scene","graphics":[[d.ptr(Pure.address(d,0x7ff34))]],"palette":d.ptr(Pure.address(d,0x7ff3c)),"palette_size":32,"tsa":d.ptr(Pure.address(d,0x7ff44)),"crop":[0,0,240,160]}
		return [compiler.effect("dialogue",[{"text":"","native_control":true,"background":path,"scene_type":"cg"}])]
	if at == 0x7e9a4:
		return [{"op":"fe7_grants","gifts":[{"character":d.u8(Pure.address(d,at)+2),"item":compiler.data.item(d.u8(Pure.address(d,at)+10))}]}]
	if at == 0xf224: return [compiler.effect("weather",0)]
	if at == 0x7b304: return [{"op":"fe7_clear_enemies"}]
	if at == 0x7f1dc: return [{"op":"scene_unit","action":"return","character":d.u8(Pure.address(d,at)+2)}]
	if at == 0x7fafc:
		# Native briefly revives the defeated dragon for its death animation.
		# Keep the battle casualty intact; the renderer owns the visual aftermath.
		return [{"op":"set","flag":d.u8(Pure.address(d,at)+12)},{"op":"focus","character":d.u8(Pure.address(d,at)+4)}]
	if at == 0x7f1b8: return [{"op":"scene_unit","action":"move","character":d.u8(Pure.address(d,at)+18),"x":d.u8(Pure.address(d,at)+4),"y":d.u8(Pure.address(d,at)+8)}]
	if at == 0x7ea0c:
		if not Pure.signature(d,0x7e9e0,44,[24,25,26,27],"3346eb00fe4c5b0305eba7d1c1dbf3e8377b37942debfd2ccb7e989e22601777"):
			d.fail("FE7 finale","Changed final speech lookup.",0x7e9e0); return []
		var table: int = d.ptr(Pure.address(d,0x7e9f8))
		var result: Array = []
		for index in range(64):
			var entry := table+index*8
			if not d.require_range(entry,8,"FE7 final speeches"): return []
			var character: int = d.u32(entry)
			if character == 0: return result
			if character > 255: d.fail("FE7 finale","Invalid final speaker.",entry); return []
			result.append({"op":"conditional_dialogue","test":{"kind":"fielded","character":character},"yes":compiler.text(d.u32(entry+4),{},false),"no":[]})
		d.fail("FE7 finale","Unterminated final speeches.",table); return []
	if at in [0x7ef7c,0x7f104,0x7f198]:
		var fixed: Array = []
		var slots: Array = []
		var excluded: Array = [38,39]
		if at == 0x7ef7c:
			excluded = [1,2,45,38,39]
			for pair in [[39,0x7f004],[1,0x7f00c],[2,0x7f010],[45,0x7f014]]:
				var entry: int = d.ptr(Pure.address(d,pair[1])); fixed.append({"character":pair[0],"x":d.u8(entry+6),"y":d.u8(entry+7)})
		elif at == 0x7f198:
			for pair in [[39,0x7f1b0],[38,0x7f1b4]]:
				var entry: int = d.ptr(Pure.address(d,pair[1])); fixed.append({"character":pair[0],"x":d.u8(entry+6),"y":d.u8(entry+7)})
		if at != 0x7f198:
			var table: int = d.ptr(Pure.address(d,0x7effc if at == 0x7ef7c else 0x7f160))
			for index in range(64):
				var entry := table+index*16
				if not d.require_range(entry,16,"FE7 final formation"): return []
				if d.u8(entry) == 0: break
				slots.append([d.u8(entry+6),d.u8(entry+7)])
				if index == 63: d.fail("FE7 finale","Unterminated final formation.",table); return []
		var header: int = compiler.Groups.chapter_events(d,"fe7",compiler.chapter_index)
		return [{"op":"fe7_final_formation","fixed":fixed,"slots":slots,"exclude":excluded,"fallback":compiler.data.group(compiler.Groups.pointer(d,header+(48 if compiler.native_route == 3 else 40))),"scene_only":scene_chapter != compiler.chapter_index}]
	# Scene-only callbacks: camera/sprite effects, final cutaway choreography,
	# read-only ending checks and SRAM support-gallery unlocks. They never award
	# supports or alter the carried army. Dialogue/backgrounds remain live events.
	return [{"op":"nop"}]

static func ending_scripts(compiler) -> Array:
	var d: RefCounted = compiler.d
	var root: int = d.ptr(Pure.address(d,0x1315c if compiler.native_route == 3 else 0x1314c))
	# The first game-control ending invokes two story scripts. The subsequent
	# closing dispatcher is handled by fe7_dynamic_ending after this story.
	if not d.require_range(root,52,"FE7 ending dispatcher"): return []
	for pair in [[0,0x8a],[4,0xcc],[12,0x98],[16,0xcc],[24,0x98],[28,0x3c],[32,0x8080481],[36,2],[40,0x3c],[44,0x807b449],[48,1]]:
		if d.u32(root+pair[0]) != Pure.event_word(d,pair[1]): d.fail("FE7 ending","Changed ending dispatcher.",root); return []
	return [compiler.Groups.pointer(d,root+8),compiler.Groups.pointer(d,root+20)]

static func valid_opcode(d: RefCounted, op: int) -> bool:
	var handlers := {
		0xe0:[0x119c4,48,"85f178718b09296955f0f7de832ac14fd147c81773f675f1928566261530a302"],
		0x80:[0xe490,24,"e81dd67d100a766f282839f4b03184ea309dd4b3045ef083f29d9e00349c63e7"],
		0x8a:[0xe65c,60,"88068f9ea9fb48fc7af2d453949d85f7e05b359fbaaba7433482c698fe51a102"],
		0xdf:[0x117ac,48,"d7671f95a542b5356c43e8343b9106c7c95d97f3f08a60dbb84daf5033d3411a"],
		0xe4:[0x11ec0,80,"246b7a24f351021b49bdb916aea2b3a5711bd44e29d2f4bfc56be6c1777ec52d"],
	}
	var spec: Array = handlers[op]
	if Pure.signature(d,int(spec[0]),int(spec[1]),[],spec[2]): return true
	d.fail("FE7 finale","Changed native final scene command.",spec[0]); return false
