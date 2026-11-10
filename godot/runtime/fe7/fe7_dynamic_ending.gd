extends RefCounted
## Native FE7 ending dispatcher and tiled staff roll. No generated files/cache.
const Pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const Runner = preload("res://engine/native_event_runner.gd")

const SPECS := [
	[0xbae58,20,[16, 17, 18, 19],"869451b0a389bb07120abfa19096063c605eb341a489f148cc72984d623e3485"],
	[0xbaacc,20,[16, 17, 18, 19],"a1bdf15b4d6510a88a773923f3caed3b0b4da785a848374f926939642ae0baa8"],
	[0xb9270,20,[16, 17, 18, 19],"966d3fc5ddb7a247800142388a5b530b2a97025a44e47542142284b8a9a13dab"],
	[0xbad64,176,[160, 161, 162, 163, 164, 165, 166, 167],"42a6d5c7b313ba0f385c5f7df792385b429636242b8d1fc771a8ff2b7f8c9547"],
	[0xbac14,336,[52, 53, 54, 55],"5107656e40cd4d82e18fe67efe615e262fc4b7e6e2ab922758f892e3074530b1"],
	[0xb75a4,56,[],"0845d9ef24d628924a34cf6fad788be7c577fd770dea50dcae45ca6b907b84ec"],
	[0xb75dc,32,[],"864983b02922d43c0fe8e9b6582d690f8955279d97742edf1dc1d36fce7f6d8c"],
	[0x31b54,28,[],"f39165ad247a4f4ec0bd8ce319ce1a86f0841c68b10300eed241008715ec1273"],
	[0x174a0,84,[48, 49, 50, 51],"400ac305ff222d071b6b9995987ae9ca67913889564367bee12606f52dc22b8c"],
	[0x174f4,128,[80, 81, 82, 83],"d7848b6e253b8699d112e78256f8c7cf28237639d7c8265cfa1f1309838f31ab"],
	[0x17574,40,[],"e3e81a1d2fdb5e21e62d37d15295292479a3e41940c965a3e845c3d20ed269da"],
	[0xa0654,40,[],"bbee18b5b769308beec00ed98dd3fbea2992905c76d5f4f0f8f8324c56a8d179"],
	[0xbaae0,308,[8, 186, 280, 281, 282, 283, 288, 289, 290, 291],"a65f439a8e81d7690d8ef4c95f1960a7b3d60a34f46769be349662fb4cd4c130"],
	[0xb7100,248,[244, 245, 246, 247],"2167d6f6bd7d9241e0a82c4fbdf97d298062405420350c50ef838f91302f4fe7"],
	[0xb71f8,56,[52, 53, 54, 55],"c8534b19c270025c69e255888a9ba55b9e0bb28f0a393a7556c4c9456ecfb403"],
	[0xb7230,248,[244, 245, 246, 247],"350f36dc2c7e4517d354fe963fb41a5903fa74131ee631a1ab4ceb5ebbfcd3bd"],
	[0xb7328,52,[48, 49, 50, 51],"8495f9f56ccf5197ae2c5f84b95ca6ed86a7e75784fa56666432aa32383488e0"],
	[0xb735c,112,[108, 109, 110, 111],"0e6ed0085304fda311135ca0a9c6a221708ab738d96447767c9e7dbad97e3b35"],
	[0xb73fc,76,[68, 69, 70, 71, 72, 73, 74, 75],"3fe589aaa5186261fb97be3c5af39cbde5f24ae68e4968996485e1822dc41187"],
	[0xb92e8,192,[96, 97, 98, 99, 100, 101, 102, 103, 108, 109, 110, 111, 112, 113, 114, 115, 128, 129, 130, 131, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191],"52c36f5d9608a5c07692a9c9722d809a75c07e7cf4327552f25a2f8e3ebcbbee"],
	[0xb9878,44,[20, 21, 22, 23, 32, 33, 34, 35, 40, 41, 42, 43],"e06d4962861d4267d9929d95ee0875011fb558bf5aa25f300b5bcb7f4b30d00e"],
]

static func compile(compiler) -> Dictionary:
	var d: RefCounted = compiler.d
	for spec in SPECS:
		if not Pure.signature(d,int(spec[0]),int(spec[1]),spec[2],spec[3]):
			d.fail("FE7 ending","Changed credits or ranking routine.",int(spec[0])); return {}
	var root: int = d.ptr(Pure.address(d,0x13194 if compiler.native_route == 3 else 0x13184))
	if not d.require_range(root,108,"FE7 closing dispatcher"): return {}
	for pair in [[0,0x8a],[4,0xcc],[12,0x98],[16,0x42],[20,0],[24,0x3c],[28,0x080bae59],[32,2],[36,0x3c],[40,0x080baacd],[44,2],[48,0x42],[52,1],[56,0xcc],[64,0x98],[68,0x780002],[72,0x42],[76,2],[80,0xcc],[88,0x98],[92,0x42],[96,3],[100,0x1e0002],[104,1]]:
		if d.u32(root+int(pair[0])) != Pure.event_word(d,int(pair[1])):
			d.fail("FE7 ending","Changed closing dispatcher.",root); return {}
	var endings: int = d.ptr(root+60)
	for pair in [[0,0x3c],[4,0x080b9271],[8,2],[12,2],[16,10]]:
		if d.u32(endings+int(pair[0])) != Pure.event_word(d,int(pair[1])):
			d.fail("FE7 ending","Changed character ending dispatcher.",endings); return {}
	return {"farewell":compiler.program(d.ptr(root+8),0,false,true),"teaser":compiler.program(d.ptr(root+84),0,false,true)}

static func story(b, key: String, d) -> Array:
	var program: Dictionary = b.chapter.get("fe7_ending",{}).get(key,{})
	var error := Runner.validate(program,"fe7")
	if not error.is_empty(): d.fail("FE7 ending",error); return []
	var result := Runner.plan(b,program,{})
	if not result.error.is_empty(): d.fail("FE7 ending",result.error); return []
	var pages: Array = []
	for command in result.commands:
		if command.op == "effect": pages.append_array(command.effect.get("dialogue",[]))
	return pages

static func credits(d) -> Dictionary:
	var table: int = d.ptr(Pure.address(d,0xbabf8))
	var distance: int = d.u32(Pure.address(d,0xbac48))>>16
	if distance < 256 or distance > 4096:
		d.fail("FE7 credits","Invalid scroll length."); return {}
	if d.u8(Pure.address(d,0xbaae8)) == 0:
		d.fail("FE7 credits","Invalid scroll speed."); return {}
	if d.ptr(Pure.address(d,0xbac00)) != d.ptr(Pure.address(d,0xbae08)):
		d.fail("FE7 credits","Closing card requires an unreviewed palette swap."); return {}
	var blocks := 7 if Pure.us(d) else 6
	var stride := (blocks+4)*4
	var count := ceili(float(distance)/256.0)
	if not d.require_range(table,count*stride,"FE7 credits directory"): return {}
	var palette: PackedByteArray = d.raw(d.ptr(Pure.address(d,0xbac00)),32)
	var canvas := Image.create(256,count*256,false,Image.FORMAT_RGBA8)
	canvas.fill(Color.BLACK)
	for index in range(count):
		var graphics := PackedByteArray()
		for block in range(blocks):
			var offset := table+index*stride+block*4
			var data := PackedByteArray()
			if d.u32(offset) != 0: data = d.lz(d.ptr(offset))
			if data.size() > 2048: d.fail("FE7 credits","Oversized graphics block.",offset); return {}
			data.resize(2048); graphics.append_array(data)
		for strip in range(4):
			var entry := table+index*stride+blocks*4+strip*4
			if d.u32(entry) == 0: continue
			var at: int = d.ptr(entry)
			if d.u8(at) != 31 or d.u8(at+1) != 7:
				d.fail("FE7 credits","Unsupported staff-roll tile map.",at); return {}
			var tsa: PackedByteArray = d.raw(at,514)
			for cell in range(256):
				var tile := tsa.decode_u16(2+cell*2)
				if tile>>12 != 0 or (tile&1023)*32 >= graphics.size():
					d.fail("FE7 credits","Invalid staff-roll tile.",at); return {}
			var part: Image = d.tsa_image(graphics,palette,tsa,256,64)
			if part == null or not d.error.is_empty(): return {}
			canvas.blit_rect(part,Rect2i(0,0,256,64),Vector2i(0,index*256+strip*64))
	if not d.error.is_empty(): return {}
	var last: int = d.ptr(Pure.address(d,0xbae04))
	if last < table or last >= table+count*stride or (last-table)%stride != 0:
		d.fail("FE7 credits","Invalid closing staff-roll card.",last); return {}
	@warning_ignore("integer_division")
	var closing_offset := (last-table)/stride*256+128
	return {"image":canvas,"closing_offset":closing_offset,"distance":distance,"speed":float(d.u8(Pure.address(d,0xbaae8)))*60.0/64.0,"music":"song_%03x" % d.u8(Pure.address(d,0xbab9a))}

static func ranking_background(d) -> Image:
	return d.scene({"graphics":[[d.ptr(Pure.address(d,0xb9d9c))]],"palette":d.ptr(Pure.address(d,0xb9d98)),"palette_size":64,"tsa":d.ptr(Pure.address(d,0xb9da8)),"crop":[0,0,240,160]})
