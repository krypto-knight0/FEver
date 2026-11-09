extends RefCounted
## Reviewed FE6 ABI callbacks missing from the stock template-free importer.
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Finale = preload("res://runtime/fe6/rom_fe6_finale.gd")
const SIGNATURES := {
	0x6bbd0:[40,[6, 10, 12, 14, 16],"7c8135c6063f9fb5bdbbf4efb8bcbd69864e330dbaa339d9019b4ce89c4ad697"],
	0x6ced8:[24,[2],"475a53c4962037c4a3980162a6777f45797ad8805043814a0c642ade2c2fb005"],
	0x6cf88:[24,[2, 4, 16],"57e38a23fdf3274bbd2b297ae5f9636d7d42f955ba6e30d5615069f4494b89af"],
	0x28e28:[28,[],"9cbf99421913d9c4fa63c60cfcb88dc33a89275675fa049b852ab009b0b118e3"],
	0x6d55c:[12,[2],"361221e23f2563a021083f5049d9c30448b8690120655103a4e1eea14468e6f2"],
	0x6cfd0:[24,[],"9395230a2a9a1481aa337965a890789666f73dd62fdc3ed94c4a8894070ddabe"],
	0x6d000:[28,[],"b465f13c98f611f2f7e4b34d3f69a9c6fbbc7e19bb77d72ee6b000980bba928a"],
	0x6d01c:[12,[],"b18a4d0b77896186efbf2cd87cd0dfc82e389140c926201ae380fe483e214d2e"],
	0x6bfc0:[12,[2],"85a89553faec602981888ae3b3f6b110c976572f046dc520d891fceb3cd76759"],
	0x6ddd4:[12,[2],"8a14e00e9e6c9f24a18e61e071b8fedbe3e477367dc8e73d5329d86e21f926ca"],
	0x6ad48:[44,[10, 12, 14, 16],"4f3e3bcd4f10998d147054dfcdad1ad327c5b86052a8f19612ea64793da73e7f"],
	0x6ad74:[80,[10, 12, 14, 16, 28, 30, 32, 34, 46, 48, 50, 52],"e38be0b2cc3907105ddc57961173bf0dc9a060c81fedbe2e0d906ccca44b5d3b"],
	0x6cef0:[76,[10, 32, 44, 50, 62],"913b42130622974c5d72e2be867c03b00e86ea81edcc3064d13d46faa9769337"],
	0x6cf3c:[76,[10, 32, 44, 50, 62],"4bc47c063c958b69c8e69b0940f86342796816bb55fba73304f65684184ca650"],
	0x6c5a8:[96,[2, 20, 40, 58],"eb8798f4325e1fee26226d7794e3107dc9656172ea94f2d0ea49d4993e61c6a3"],
	0x6d028:[60,[18, 22, 30],"764559b34b7ed8ab2293b15c4bdf4b4d66adc670cb6f6f553b99b84b3049ccb0"],
}

static func verify(d, at: int) -> bool:
	if not SIGNATURES.has(at): return false
	var s: Array = SIGNATURES[at]
	if Pure.signature(d,at,s[0],s[1],s[2]): return true
	d.fail("FE6 compatibility","Native callback changed at 0x%x." % at)
	return false

static func query(d, address: int) -> Variant:
	var at := (address-0x08000000)&~1
	if not verify(d,at): return null
	if at == 0x6bbd0:
		if not Finale.verify(d,0x6acec): return null
		return {"kind":"fe6","test":"turn_area","after":d.u8(at+6),"rect":[d.u8(at+10),d.u8(at+12),d.u8(at+14),d.u8(at+16)]}
	if at in [0x6ad48,0x6ad74]:
		if not Finale.verify(d,0x6acec): return null
		var rectangles: Array = []
		for offset in ([10] if at == 0x6ad48 else [10,28,46]):
			rectangles.append([d.u8(at+offset),d.u8(at+offset+2),d.u8(at+offset+4),d.u8(at+offset+6)])
		return {"kind":"fe6","test":"areas","rectangles":rectangles,"outside":at == 0x6ad48,"phase":"enemy"}
	if at in [0x6cef0,0x6cf3c]:
		if d.u8(at+44) != d.u8(at+10) or d.u8(at+62) != d.u8(at+32):
			d.fail("FE6 compatibility","Delayed reinforcement flag pipeline changed."); return null
		return {"kind":"fe6","test":"delayed_flags","flags":[d.u8(at+50),d.u8(at+32),d.u8(at+10)]}
	if at == 0x6c5a8: return {"kind":"fe6","test":"experience","left":[d.u8(at+2),d.u8(at+20)],"right":[d.u8(at+40),d.u8(at+58)]}
	if at == 0x6d028: return {"kind":"fe6","test":"desert_find","classes":[d.u8(at+18),d.u8(at+22)],"denominator":d.u8(at+30)}
	d.fail("FE6 compatibility","Unsupported native query.")
	return null
