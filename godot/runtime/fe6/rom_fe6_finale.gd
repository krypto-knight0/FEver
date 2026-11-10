extends RefCounted
## Reviewed finale callbacks. Instructions are fingerprinted; content operands
## (rectangles, item lists, flags, formations and text) come from the loaded ROM.
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const SIGNATURES := {
	0x6baa0:[24,[],"b17f4858293b0476126f3eb17e06fcc141e7347ca946eaa8a49d3ac43ddc0708"],
	0x6adc4:[24,[2, 4, 6, 8],"2371dd4f7911795334fee803b32732d06cf9d1787a7ce70032aa91fcc1db04bd"],
	0x6addc:[40,[10, 12, 14, 16],"e99c763297eb8a681b6ee91943e1d5a5423374c43cdaf600a3ec71303edfb0aa"],
	0x6ae04:[40,[10, 12, 14, 16],"dcd455bce2ca4459086da4521bd2df4613b87922e4d855bb8e315e1a12b86647"],
	0x6ae2c:[40,[10, 12, 14, 16],"c4a76b29701c849fdc4bd40332dc8ab0578ea0f6e5d7922e707e6ba4c658c1b2"],
	0x6ae54:[40,[10, 12, 14, 16],"e0a4ccc8f736e0f33f244bee8540766c3cb2f205f0dd51034c4e9c75e10a4c96"],
	0x6acec:[184,[],"1cb601934ee8a0eb01724ed55b2dd79a94ceeb94a43d73ad677ad2b5d95a991c"],
	0x6bc5c:[72,[10, 22, 44],"f64398f27a982cf01359d2af469bd1b13a82f0551810834361324e4828bacf0a"],
	0x6bca4:[72,[10, 22, 44],"4377878c948d4b2d75651ab66b9c12f952de3bcc1572f5dddc932c951bab3bf0"],
	0x6bcec:[72,[10, 22, 44],"d0b437a369db62c55920a645a04091a8e94f4214ab2dba37a6be8c8749ad162f"],
	0x6bd34:[72,[10, 22, 44],"b1b5186f98a381eb48f20645be4e991ddf357f235e5ece9b2b779187e4ea3add"],
	0x6bd7c:[72,[10, 22, 44],"1e801edbc1c50d393593dc3b7c17adf5aa1c734c9ca13c1a19d7a695ac84d472"],
	0x6bdc4:[60,[10, 32],"3c1dbdc65a2d1885476c8c6607796bf0ab04fbb6aa7c6aa025854830961e96c4"],
	0x6d150:[44,[8, 9, 10, 11],"5ebff41ae27afe65f9db5f0ecdbe911922a78ddbb7d533a0d0a75f09bb28cb62"],
	0x6d0fc:[84,[],"0c081bb6020e8ec550a628516f484d28c1de76154179dcb86b910c994db6d805"],
	0x6c500:[36,[],"3ab04f0e9ed8133c6a73e20b9921630ef06047c2250c0e6c1072553358bcf167"],
	0x6d0e4:[24,[],"5ab3c6ef6bfa04e9173407d43abcb41c645dc93eb20f1adf35b27321b8d52bc5"],
	0x6d17c:[24,[],"a3ee0aa834d368555dc6929a63fea92f34cfb668c8c5f36cdb932de3036a4b21"],
	0x6d194:[24,[6, 14],"42585c709ca03a5ee99f465487e62498e8926f9b0c83a4e9cc86e4536a8df0c8"],
	0x6d1ac:[40,[6, 30],"82adfb140e3fbe02c82e84bfbde5352888b5ddf1d7b2ec6379325e8ea40d4a4c"],
	0x6d6d8:[164,[2, 4, 10, 12, 18, 20, 26, 28, 34, 36, 42, 44, 50, 52, 58, 60, 66, 68, 74, 76, 82, 84, 90, 92, 98, 100, 102, 108, 110, 112, 118, 120, 122, 128, 130, 132, 138, 140, 142, 148, 150, 152],"eeb830ce09baa3e62033eb2c11fc5b16c285ba3ff0a4819095d8c251bd6540b1"],
	0x6d77c:[76,[10, 36, 54, 64, 65, 66, 67],"d9db7f3580e438749a266116b57ef91ca78ffa52f80a01442b37eb499dc80dd7"],
	0x6d35c:[60,[42],"01a8e64de4b45ff39e6a5699777f3db8d63c8644524cef2f09b7b9e181488f2f"],
	0x6d398:[28,[],"4aca061a0d08fd45f00e628c0ba10a3a6cc797483eb160cb3982a380a5b6cfd2"],
	0x6e278:[48,[12, 26, 30],"bb1eeaad0c27a4088b7595c87e7e8709db8ac85626e55714d54a2c220c2096c4"],
	0x6e2a8:[76,[6, 10],"56b9f93394346f8285a505406062c354e45f540923f4b2b61da9bbdf2a660325"],
	0x6d1d4:[40,[],"9ac6ee5a402081761ed65fedf93cb69b75a99eb17291a81eac3a4862d39a3156"],
	0x6d1fc:[352,[],"723994f791aae4d6de5fb263505d8ebc5680b8caf6cb3b968c0baa236d1c7aae"],
	0x6de00:[32,[],"7c034f40354116bbf8987182a7e7086ebe531ccbcd6e7b8b4a2832bbb1740a4e"],
	0x6de20:[12,[],"5d913a6206a6c35eb98407e6040dc0874bf7ac97a82475a9182ea3cbbca02bae"],
	0x124a8:[188,[],"cab4b4adee40d9de99b0ecc7c038c6f6faaa15f071d5a15f17abb33f8edda33f"],
	0x12564:[32,[],"152c5a3dc3f76f0ce638ddbea62b19c8c09840b9d47c08ce9e798a088df19862"],
	0x190f4:[32,[],"dcf686a4d6aeca3babba0eb3d900de53979963c2739a902e8faaa99f0a64757e"],
	0x22094:[32,[],"80bea1cd358c19ec7445443228482e65dab960b9a757085a0ecb8e2bfb40fec6"],}

static func recognized(at: int) -> bool:
	return SIGNATURES.has(at)

static func verify(d, at: int) -> bool:
	if not SIGNATURES.has(at): return false
	var s: Array = SIGNATURES[at]
	if Pure.signature(d,at,s[0],s[1],s[2]): return true
	d.fail("FE6 finale","Reviewed callback changed at %x." % at)
	return false

static func query(d, at: int) -> Variant:
	if not verify(d,at): return null
	if at == 0x6baa0: return {"kind":"hard"}
	if at in [0x6adc4,0x6addc,0x6ae04,0x6ae2c,0x6ae54]:
		if not verify(d,0x6acec): return null
		var offset := 2 if at == 0x6adc4 else 10
		return {"kind":"fe6","test":"area","rect":[d.u8(at+offset),d.u8(at+offset+2),d.u8(at+offset+4),d.u8(at+offset+6)],"phase":"any" if offset == 2 else "enemy"}
	if at in [0x6bc5c,0x6bca4,0x6bcec,0x6bd34,0x6bd7c,0x6bdc4]:
		var last := at == 0x6bdc4
		return {"kind":"fe6","test":"wave","enabled":d.u8(at+10),"disabled":0 if last else d.u8(at+22),"cap":d.u8(at+(32 if last else 44)),"parity":1 if (d.u16(at+(30 if last else 42))&0xff00) == 0xd000 else 0}
	if at == 0x6d150:
		if not verify(d,0x6d0fc): return null
		var table := Groups.pointer(d,at+8)
		var items: Array = []
		if table < 0: return null
		for i in range(32):
			if not d.require_range(table+i,1,"Legendary weapon requirement"): return null
			var item: int = d.u8(table+i)
			if item == 0: return {"kind":"fe6","test":"items","items":items}
			items.append(item)
		d.fail("FE6 finale","Unterminated legendary item list."); return null
	if at == 0x6c500:
		var characters: Array = []; var classes: Array = []
		var people := Groups.pointer(d,0x17680); var types := Groups.pointer(d,0x176e0)
		if people < 0 or types < 0: return null
		for id in range(1,226):
			if not d.require_range(people+id*48,48,"Personal attributes"): return null
			if d.u32(people+id*48+40)&0x4000: characters.append(id)
		for id in range(1,77):
			if not d.require_range(types+id*72,72,"Class attributes"): return null
			if d.u32(types+id*72+36)&0x4000: classes.append(id)
		return {"kind":"fe6","test":"male","characters":characters,"classes":classes}
	if at == 0x6d35c: return {"kind":"fe6","test":"nonblue_count","minimum":d.u8(at+42)+1}
	if at == 0x6d398: return {"kind":"ambush_roll","denominator":d.u8(at+6),"cap":128}
	d.fail("FE6 finale","Unsupported reviewed query."); return null

static func action(d, at: int) -> Variant:
	if not verify(d,at): return null
	if at in [0x6de00,0x6de20,0x124a8,0x12564,0x190f4,0x22094,0x6d1d4]: return {"op":"nop"}
	if at == 0x6d0e4:
		var people := Groups.pointer(d,0x17680); var classes := Groups.pointer(d,0x176e0)
		if people < 0 or classes < 0: return null
		var character: int = d.u8(at+6)
		var base: int = d.u8(people+character*48+5)
		return {"op":"fe6","action":"promote","character":character,"class_id":d.u8(classes+base*72+5)}
	if at in [0x6d194,0x6d1ac]:
		return {"op":"fe6","action":"clear_range" if at == 0x6d194 else "increment_flags","flags":range(d.u8(at+6),d.u8(at+6)+d.u8(at+(14 if at == 0x6d194 else 30))+1)}
	if at == 0x6d77c:
		var table := Groups.pointer(d,at+64)
		if table < 0: return null
		var flags: Array = []
		for i in range(d.u8(at+10)):
			if not d.require_range(table+i*4,4,"Chest lottery flags"): return null
			flags.append(d.u32(table+i*4))
		return {"op":"fe6","action":"lottery","flags":flags,"count":d.u8(at+54),"denominator":d.u8(at+36)}
	if at == 0x6d6d8:
		var traps: Array = []
		for i in range(12): traps.append({"x":d.u8(at+2+i*8),"y":d.u8(at+4+i*8),"type":"fire"})
		for i in range(6): traps.append({"x":d.u8(at+98+i*10),"y":d.u8(at+100+i*10),"type":"pike","direction":d.u8(at+102+i*10)})
		return {"op":"fe6","action":"step_traps","traps":traps}
	if at == 0x6e278:
		if d.u8(at+12) != d.u8(at+26): d.fail("FE6 finale","Battle weapon comparisons disagree."); return null
		return {"op":"fe6","action":"save_dragon","item":d.u8(at+12),"flag":d.u8(at+30)}
	if at == 0x6e2a8:
		var presence: Variant = Pure.describe(d,0x08000001+Pure.call_target(d,at+22),"fe6")
		if presence == null: return null
		return {"op":"fe6","action":"ending","chapter":d.u8(at+6),"flag":d.u8(at+10),"character":presence.character}
	d.fail("FE6 finale","Unsupported reviewed action."); return null

