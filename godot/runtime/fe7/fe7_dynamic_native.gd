extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## Reviewed regional FE7 callbacks. Never execute cartridge ARM code. Fingerprints cover
## complete helper bodies; only explicitly decoded data operands may vary.
const Pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const HELPERS := {
	0x11b30:[28,"a881faa2314ff38ed93dec1f4c87f2607d58e030def31c1fa2400266c92d89db"], # Wait for scene sprite effect.

	0x7e750:[36,"b414261771f87bfc74e9968de40141a76c1f40a1cbf7023fa156107b7d471b4c"], # Read-only timed-defense ending checks.
	0x7e904:[4,"6c1871acd4bd9950e81b2850fac7ddd44f28500d6bba63991c2599234ddbe61c"], # Empty preparation-map ending helper.
	0x7d938:[20,"171d29045eea5c565f2003e592685661a0913c70745e7ef870e468efa98f17c4"], # Chapter transition iris display process; no gameplay state.
	0x7d95c:[16,"c79c3509b375a8a0fe98b098801ce20d650180d9efcad0cfe280b07b2dd49e2c"], # Unlock a conversation in the SRAM support archive; no combat support gain.
	0x7e934:[28,"6ebd705c20b254279261deccccc14c37a89d61827c8b22a46f8bbd01c1b127ab"], # Read-only seize-map ending checks.

	0x7b7c8:[40,"e29c094811a60cec998c2c78c8ec44bcc32de7dd096985130af87339c15b7339"], # Stop vertical scene shake.
	0x7b684:[68,"b2c91050124b70d8a2deb4389b4a4b6a826ae9533767b68b7e79ec651225a619"], # Vertical scene shake.
	0x7e574:[16,"4fd09f72aefbc402caf3cb233e4a1a38d30910ed8ac5616a5d09203cec4f82f3"], # Read-only rout-map ending checks.
	0x7e584:[80,"099f74cb917943d15a41320932f5ab8198a5af96c1746548ee7c9340ce67d5b3"], # Scene antagonist sprite effect.
	0x7d94c:[16,"aad65e4381fedbed8b3076b8d42c017cec32681302818d730d8718192c3e7f2f"], # Unlock a paired conversation in the cartridge SRAM support archive; no unit support gain.
	0x7e5d4:[12,"8e719846d61d08c6d91e155683bc31026984a7f07dbde284dd3fa29c2b11eefe"], # Read-only Roland ending check.
	0x7e5e0:[68,"56c6fd03047f2bdcfb840267d4b17b22a0c7920558e34ed4f7f68688ddb5463f"], # Start legendary weapon glow.
	0x7e624:[24,"cee3dc5b7a0de194106bebe320baf67d973a5530fe8866659946b1fc1f3e7508"], # Stop legendary weapon glow.
	0x215d0:[24,"95a2d1689b952c44da17bbb8c90501d94ce67d3a5982c6b45cc831a402adaa06"], # End legendary weapon display process.
	0x7e63c:[28,"6b77515e468a66e590fea4a3038362b53c38074c743adf416301088a6f2beff0"], # Start legendary weapon scene effect.
	0x7e658:[60,"d88561a22c1aea1c9e715a0d8d8407ae8341740e2dac4bceda52509239fca8eb"], # Remove the temporary legendary weapon actor.
	0x7e694:[16,"e72ac3e50a926ffa0a07d6a6cf7caba3994dd86d79cae3ee090c1c3ea349ef7c"], # Hide legendary weapon actor sprite.
	0x7e6a4:[120,"27cfd0b52dd7f73270402dad5c68b8c04aec7b2d846a848e91fea2480113da24"], # Legendary weapon sprite effect.
	0x7e71c:[24,"6070ef448b72872769b17a1e02b18f2091a3b8306b609463091fefc14eaa24a9"], # Restore legendary weapon sprite.
	0x7e734:[28,"b7c243bfb9deecd91dbcf6020316edd7e389d1ca4b91cb6e07088a4c30568422"], # Read-only Berserker ending checks.
	0xb7070:[20,"956ce7f57198eab0d0b2d103ae7f6c57848c0f0129def0770bc94941d03345f1"], # Scene transition display process.

	0x7e2f0:[80,"b5e97d0e7dd175522f9616be6fdb2ea20641e003ad99bf6de652eba7fce666bc"], # Scene actor effect; no persistent battle state.
	0x7e378:[68,"69fb7e1f9512eeb1a91bd5349b48480058da51c7dd2a822de9a867dd41bdb90a"], # Start horizontal camera shake.
	0x7e3bc:[44,"664bc5e0f43ecdac2f51386654a43b28359899a4a70f5f04c653c513863a0540"], # End camera shake and align camera.
	0x7e444:[96,"c1173c2a6641c9c6c2ba4904e16ea32855af8624103802caa776aa1d42e5d95a"], # Scene palette flash process.
	0x7e4a4:[28,"84094024a72db0e9301086b31f7e9b865dbb63113257e45fbc78be3ac5101710"], # Wait for scene palette process.
	0x7e4c0:[40,"db8c5068390dd0c14e1a25d0875d80f11c804f51a608fb40307e944bfa958e81"], # Temporary morph scene sprite/class; actor is removed by the script.
	0x7e4e8:[44,"5c2aa34c52edf2590f8bd83033f74a177aa5c1a53dafd197faee4632305ff8a5"], # Morph scene sprite effect.
	0x6d4a4:[24,"da1d35650e8356cdcfa234836105b4151a8e91bbd21ad9be14222959f0bcc7b4"], # End map sprite effect process.
	0x7e2a0:[44,"88d1b2512d4db42f8bb001f2ea620e8f9be241c1b71c9d6a255f2e9a4c0bdec8"], # Read-only palace chest/recruitment flags.
	0x7e2cc:[36,"81cf6e711c350fa5ffe21ba3acc779c0ad69f1fd9490f0fc4ad07eaff7dbbf91"], # Read-only island chest/rout checks.
	0x7e0c4:[16,"09cbedb8745b93db050d3eb421049db170d326a78252d28cbf76e4569eebc47b"], # Read-only chapter ending checks.
	0x7e178:[16,"453888474f78385ef34b987a6ec96ba39fc22db02404cb065eb1d248b4947433"], # Read-only chapter ending checks.
	0x7e1c4:[36,"8ed5df2a48831e34f5c864d267e3074bf059f26c31f0fd10d6fc57aa2338e28a"], # Read-only chapter ending checks.
	0x7e27c:[36,"cd3ffa7d1d20d18b347643f0d046ccb7d3f7e1f0f0c569b082393e65f46a764d"], # Read-only chapter ending checks.

	0x7defc:[16,"98a06fee69d38f006e92e0ad71147e33f191e5f69d638c33dbd66bc86a0f2be6"], # Read rout and boss flags; no side effects.
	0x7dfdc:[24,"0bf9fe39bd023fb57317d9137303754c7cf9e8e74beee9bba0138cf889cf73f0"], # Magic-seal arrival display.
	0x7e018:[32,"f2f1f4d18c38cbbb721443fa6d1bfdd0a431532fd1d8e2432109546b60550447"], # Read chapter flags.
	0x7e038:[24,"fd1b4cee710c853f8c60f3c66440fb9f8cc6333537de68627b78a61a0f61d2d1"], # Read chapter flags.
	0x7e050:[36,"0ed6d3f7feed0cf55954faaaa4a721a8ff28f5119a510566aff66b12a03d6a99"], # Read chapter flags and rout.
	0x7cd60:[24,"a89a3569158c41ad5d51c99d92d29dab741adc2ef47b47cd87dfe3203fb275fd"], # End the reviewed portal display process.

	0x7dea4:[28,"51d8c785ba91bc3528655b749343606c4a1ae4b842680464122c9c2698bd15a4"], # Read-only Kinship Bond ending checks.
	# Reviewed display/portal processes; hardware palette/ripple effects are omitted.
	0x7b400:[48,"d34316108d8396a7e393d352615b0b10054b5658edba79767712761b2ac4d60e"],
	0x7b70c:[68,"63b0581341282db36f14366acb44c4e61b41526ba5dc413384fe7faeb2181bd9"],
	0x7bc54:[20,"7200607c4eb4450a1ccc9b1f584a5c8a677081289e50ca9e0b28841b24bdf860"],
	0x7bc68:[24,"3e90a39d47acb7c4c3450e7dc2b59bf956ef9ed14c1b804db5a3461f1ea0dc8b"],
	0x7bc80:[20,"392cb18321f44abdf33e6f7d21f261e66f4243bbe9696b1b3a68c71add8bf0f7"],
	0x7bcd8:[20,"c65948e3dba82ea8b6fae49ed5a47dbe7957b3f3bec1be8dbe77d255100fdc90"],
	0x7bcec:[20,"4dd9bb606f350f87d12960e152fc3aa8cbd374ddbdeae5206c5d25e5b2d8eeec"],
	0x7c1e8:[20,"64a4b61dd60139e73bb87e18b45dcf582104901db9f598f86588f329005badb4"],
	0x7c1fc:[20,"9dcae41fc2d095f70c60f81d44377ca7eb3a2094bb7a937a11fd9607381954af"],
	0x7c210:[24,"014d464be5c848fd4c8c9fae8fd4fbd49f6f921e6487d184b013cd80ed48ba70"],
	0x7cd34:[20,"8f2ab9243e0bd548bec89749153d1f1326294034b4209e2679389b9fac827e0c"],
	0x7cd48:[24,"3081f549114934661258a4ec6b31885c70a17d428de86c0ff208e22ffe94b150"],
	0x7cd78:[20,"7ddb88fa2826b18326f8b36fd6308789e46b1355f565d419c584a82b671b79ff"],

	0x198ec:[128,"830b1cfe05188a8b81b8913e63b9937505f06aa8ea7db6cac9615fbb291227bd"], # Redraw map tiles and enable display layers.
	0x20f20:[24,"25abdc377add06b094d6809f6b6511af2b9394eafa834981888d12dcc6dd85d6"], # Wait for warp presentation process.
	0x7b4e8:[76,"121981b8bd11a5e8815b7e9384afd3c68f315df143957235f8dcd876574b63b1"], # Set CG-to-map blending layers.
	0x2516c:[24,"15f0e06dd9845a80d1a4c8086abf2d66ecdd173fabd5468194b27f1a2466372c"], # Load scene sprite palette.
	0x7ddcc:[16,"32c0645dc7ec9e41b34d52bfecf07640556c4c0d3ae266c0ddff3be373b490c7"], # Read-only magic-seal chapter ending checks.
	0x7de08:[4,"6c1871acd4bd9950e81b2850fac7ddd44f28500d6bba63991c2599234ddbe61c"], # Empty gaiden ending helper.
	0x7de0c:[48,"7f33c0c1bb7d893d86b4a1dfeb60ba2a124c6082f572b86e41069942aca6a2de"], # Read-only gate-map ending checks.
	0x7de3c:[48,"63de1a1ccb58d1f125b2d399af80a70561130ea496486eea9342b672cc747006"], # Set scene background priorities.
	0x7de80:[36,"0ac15a4df234e62f2230182dab131b9fafa3295bda483365442fb319328d56b6"], # Read-only New Resolve ending checks.

	0x7b7a0:[40,"67b709c64fd662d169c25b060156c4a641ce44668333e7d612ca494eb1e99c5a"], # Stop horizontal screen shake.
	0x7b6c8:[68,"0a031ccfba5341fa6de484345dcefe223b5a73222b43297a34c9860e83d216f9"], # Start horizontal screen shake.
	0x7dd84:[40,"89bb35bb4e10fe220fe958e14f276dce354c396e03c7376d8f71a57e2c464890"], # Read-only port ending checks.
	0x7ddac:[16,"3d1abb9b7b25ca77071f044f6205a5099f8947019da12747641229a3423b2854"],
	0x7ddbc:[16,"c58faaafacf4f5d45701a6f2ebbf005e501296e6ee65bb2477c4056a8ea20d7a"],
	0x7dc9c:[52,"330d427172d4c46c33360f9dbe4fbdae190b8b1753ad66969cacc0471f801ca2"], # Read-only prisoner chapter ending checks.
	0x7dbb0:[24,"feff3c442ca113399e8237ea4e5134111085030489233a1dfe7a6edf8a3f011b"], # Read-only castle-map ending checks.
	0x7db20:[28,"427134d6f1743f69071f5ff0737e9b281ed0ac7399d1dc02895b3859b3631e1c"], # Read-only route-3 defense-map ending checks.
	0x7daa8:[28,"fc0a5ee1c256782a50a2fc7638223a58a0884690e3aaeb9cc4c59f476ed9e4ff"], # Read-only chapter 13 ending checks; return value unused.
	0x7dac4:[16,"2ffc7db24c37b3e399092cbbaab93449376fe9484b4cdd8a04e0a8863d121c7b"], # Read-only chapter 13x ending checks.
	0x7dad4:[32,"18bd2cd085b51d793d51e31d92483aa983cb5d634d53a8952f7704cb8ca28a20"], # Read-only chapter 14 ending checks.
	0x7da74:[16,"691ef8d2e7b5302a0a13440cc1d8a83fa9ff7bf85c043bbd8676ee95f23f419a"], # Read-only ending checks; returned value is unused.
	0x7da84:[16,"ece47d64b8654b48c545792f98074475b5be682c7cef45fee5030c0a6e76df55"],
	0x7da94:[20,"2257daf362b49416395f0789c6d764466d17285d6d40b265f54fe37993e6632d"],
	0xb9270:[20,"ec70b2adf6d48ed36385628414208d51574712ca402ec40178c62a281588d966"], # Start native ending-roll display; port uses its chapter completion panel.
	0x15a0c:[60,"d836e83faab5a1009a9f0fd59b3f4a059bf92167beeafa8b29dfc294e983e965"], # Upload yes/no textbox tiles and palette; the port renders its own buttons.
	0x1d154:[48,"8654be29b57d1a8d696e9b84e0dc9ad10ee0449f19863d7123e92780bdead603"], # Roll back forced tutorial move; free-control keeps the chosen move.
	0x1d6d8:[16,"fcf754ce12a684708455f15e27f46832f7b60c26feef6e314a21f1b62db803cb"], # End range-arrow process.
	0x7af3c:[20,"8dba3b16f4cd0d513c7ae5aaa2b1078a46f5dbe5d85567c143b7d5da0ef6048c"], # Forced-input process; no input locks in this port.
	0x18c20:[88,"1b94b7cf10ea297b8e228834ea61dca89a402ecd72f0aaba214809c88f5d39c5"], # Temporarily revive for the scene, then clean up; keep casualties dead here.
	0x18c78:[76,"aa5d9b6e124f75afd5fc219354c704deb5b19fa30214ea9d2881368614bf2950"], # Restore temporary scene casualties (we never revived them).
	0x7b24c:[92,"490ab7db4273af19d1c4c1085844b3ce68adc683b7307e2de437a43c4f3e15da"], # Hide player slots stacked on the route lord.
	0x7d9e8:[20,"9aae030a51e20c312b94ccd04b17984b611451b2822b6b3da32d89c6559b430f"], # Refresh unit/fog maps and sprites.
	0x7b2dc:[40,"2921b8b746fdcbbf6a80fe4ba0aa11d4ff0db845f460e5c3577c85b91b6be862"], # Clear nonplayers without healing.
	0xec08:[28,"46edd7f359039c35f09836053e3dcb6971a33a05f7b67b66ad454317c9528f5f"], # Clear text/face display processes.
	0xebbc:[76,"61c0a6b62957fbe2caa4e3c5e815b6230dc0c23a5b3c4f2fe00adaa92874cba1"], # Close/fade text process; dialogue renderer owns this presentation.
	0x7da3c:[12,"cf5935204770978244ba149d708a18d900744b2e535207fe515cff4f2de3c7b9"], # Protected NPC defeat sets chapter flag 23.
	0x7b3ac:[36,"3478c40d4872222f9bae5b8cd7324adceb1cf598b14f030f45ffe0b2ad2d5fe7"], # Suspend map rendering.
	0x7b3d0:[48,"3a0b70140a74c287f6ef818416f0d981ea6b2a2ea1a1c0a76ebbbf5bb7f69c0f"], # Restore map rendering.
	0x7b448:[48,"3b809ff03407f91221ab09c43ae7e5097268b2bb808da0e34cf2e0b29b502034"], # Clear display layers.
	0x83b80:[28,"2c66faebeb7f2463bf1cf192d8c998d56bf87a21316ecf2414717a5acd203194"], # Wait for tutorial textbox.
	0x7b228:[36,"9cdaecce3a2b7ec68a604bdf2c0cdd16e543487ee3a3c5f983e0cdc9ec18e00f"], # Wait for cursor/text process.
	0x4b29c:[32,"5264b450abde8b8eaa9bbe8c0fcc17960a87d8b200587be56956a2f487f58831"], # Suspend command menu.
	0x4b2bc:[32,"c21ec91db8e1fe164fef4db8b8976c3358711741f0450feb07b20ee697652433"], # Resume command menu.
	0x7b32c:[128,"a7b845a12fa499b91b84bb15eb205282877f4fff9ba19b7efdd177664266ee53"], # Clear nonplayers and heal surviving players.
}

static func callback(d: RefCounted, pointer: int) -> Dictionary:
	var at := (pointer-0x08000000)&~1
	var helper := Policy.identity(d,at)
	# US ending unlocks a sound-room entry; the port already exposes the full library.
	if pointer&1 and Policy.us(d) and at == 0x7f1d4:
		if Policy.Shared.signature(d,at,16,[],"ec19ed72438f0f4b65fb8d5c963e311ea78e6f8ecb66d4576281bf48a1d0d71c") and Policy.Shared.signature(d,0x9f748,68,[],"dc06b828b24462d05c7098b1489eaeafb49ce09943c91fa22d70bc2cc9cd1058"): return {"op":"nop"}
		d.fail("FE7 ending","Changed sound-room unlock helper.",at); return {}
	if pointer&1 and preload("res://runtime/fe7/fe7_dynamic_finale.gd").SPECS.has(helper): return preload("res://runtime/fe7/fe7_dynamic_finale.gd").callback(d,helper)
	if pointer&1 and helper == 0x7d938:
		if not (Pure.signature(d,0x7d938,20,[],"171d29045eea5c565f2003e592685661a0913c70745e7ef870e468efa98f17c4") and Pure.signature(d,0xd6fc44,56,[],"39bd14204689dfd1daffc93bcfdcb3c76ae065c0f9b8f065ab505a8cdd6151ba") and Pure.signature(d,0x7d6e0,600,[],"f7df91303e544489d02969e08b9abc26d4c6409a37f2d34f443be06841174341")):
			d.fail("FE7 scene","Changed chapter transition process."); return {}
		return {"op":"nop"}
	if pointer&1 and helper == 0x7e854 and Pure.signature(d,0x7e854,176,[],"c74dd8e2b87716749f833246eecb8e365d7fd90400569c61aee8b009a3f1908b"):
		return {"op":"fe7_casualty","character":d.u8(at+4)}
	if pointer&1 and helper == 0x7a568 and Pure.signature(d,0x7a568,40,[],"c25be1ef1fc5cf417b0beba9be9d7aec971a2f5f980e49c8c5c36efcf1f52cae") and Pure.signature(d,0x29cc8,236,[],"3623dbb433efb23312ad982b2938681aacf5039c4c49ec865524bd2b64691c9f") and Pure.signature(d,0x2d148,160,[],"3dad7044ea5da5c5da224801eb1f6a02e5a28beddf0c05a838495a04227c0978"):
		return {"op":"fe7_promote","character":0} # Compiler resolves the campaign lord.
	if pointer&1 and helper == 0x7e090 and Pure.actual_signature(d,at,16,[],"37cabb6c606ee12cdfbd62dc02d95cad3fbc754aef6dd525c63440d9cc5dec7a") and Pure.signature(d,0x7a6bc,28,[],"ffcd603702689f9fcdfb86d6304bfa28a97ea45889e2e72dbec666a7bdb5b6e4"):
		return {"op":"spend_gold","amount":d.u32(at+12)}
	if pointer&1 and helper == 0xf230 and Pure.actual_signature(d,at,12,[],"e59c4587b7505a8004c91eb7a632829dd4cd6ed9ab5c92f2d89134df90be79b6") and Pure.signature(d,0x2e368,24,[],"95b3c1f14b3656f9818aed6868b5590728b73c70663c7cbf61471c606a4caaa5"):
		return {"op":"effect","effect":{"weather":d.u8(at+2)}}
	if pointer&1 and helper == 0x7df0c and Pure.actual_signature(d,at,56,[],"d5b0237a91ff46a993f79a0a8a3cbd3789f791e1eb14f89b0ea32c96be006274") and experience_getter(d):
		return {"op":"fe7_exp_baseline"}

	if pointer&1 and helper == 0x7de6c and Pure.actual_signature(d,at,20,[],"5a50f8cd81bcb133355ca69364dba22f3c8d80c62f276952018b027fe590845b"):
		if not Pure.signature(d,0x179f0,16,[],"83dbb71759c1d99edee9e5be8135a58a2cb2842916d2c3593c8bdf29bac7a6af"): d.fail("FE7 performer","Changed native unit update helper."); return {}
		return {"op":"fe7_ring_status","character":d.u8(at+2),"bonuses":{"def":10,"res":10}}
	if pointer&1 and helper == 0x7b478 and Pure.actual_signature(d,at,32,[],"d3a25ecb5401266969ab9a1780dd946b66de102a51eacb3c5a49d0713ba5d189"):
		if not Pure.signature(d,0x270c0,152,[],"60ba6c8771644e4d1f8b2e404e5da38588321ea577e0e60b9b278a64bd7452e6"): d.fail("FE7 performer","Changed native unit update helper."); return {}
		return {"op":"fe7_performer_swap","first":d.u8(at+2),"second":d.u8(at+10)}
	if pointer&1 and helper == 0x7b8cc and Pure.actual_signature(d,at,12,[],"ea07c7846788b438d2c943b2f09bd55c54120819b6b0dc66eac2cd32bb2d325f"):
		return {"op":"set","flag":d.u8(at+2)}
	if pointer&1 and helper == 0x7b8d8 and Pure.actual_signature(d,at,12,[],"9d4daa3c84179b28a13ac81749957c01e38e6969c29325b4032eb749d859ff94"):
		return {"op":"clear","flag":d.u8(at+2)}
	if pointer&1 and helper == 0x7da64 and Pure.actual_signature(d,at,16,[12,13,14,15],"2143247d92099f9d7432a548bd162f10cdea0db17d55d479aad56973b3fad394") and Pure.signature(d,0x23d9c,24,[],"3e934187b484fe0c4e8483db04acc5b9ff7438397afd333b2f946f12109be482"):
		return {"op":"set_gold","amount":mini(d.u32(at+12),999999)}
	if pointer&1 and helper == 0x7db3c and Pure.actual_signature(d,at,80,[],"1050f1e0907c2c185e35baa432b327a5defc3105d8aa101e35b229f8a3965f43") and Pure.signature(d,0x17a44,32,[],"4bedd0e60f157fc8ccc77eb55d242c9febd84fbd8b0bfcf341c669c0acc59fed") and Pure.signature(d,0x165f0,48,[44,45,46,47],"aece3e061ff6a39b66ea7b1975a5576608c407a235c9d5dd80a94590fae24628"):
		var bonus := {"op":"fe7_bonus","character":d.u8(at+52),"flags":[d.u8(at+16),d.u8(at+4)],"items":[{},d.u8(at+46),d.u8(at+24),d.u8(at+30)]}
		if Policy.us(d): bonus.default_without_lyn = d.u8(at+94)
		return bonus
	if pointer&1 and helper == 0x7dbc8 and Pure.actual_signature(d,at,184,[],"948b4f2f39c42ad771098f44a3586cdcddebf01df982ae3b7c26aead682933b5") and Pure.signature(d,0x17a44,32,[],"4bedd0e60f157fc8ccc77eb55d242c9febd84fbd8b0bfcf341c669c0acc59fed") and Pure.signature(d,0x165f0,48,[44,45,46,47],"aece3e061ff6a39b66ea7b1975a5576608c407a235c9d5dd80a94590fae24628"):
		var gifts: Array = []
		for index in range(8): gifts.append({"character":d.u8(at+2+index*22),"item":d.u8(at+10+index*22)})
		return {"op":"fe7_grants","gifts":gifts}
	if pointer&1 and helper == 0x7a5d0:
		for part in [[0x7a5d0,80,"d6f5ebfd6f66456f73699d9346e205f85560c99abb3dea696a9b2090d06e1787"],[0x7a620,40,"69d44a81de2ad29d00d2dcb0055805dc1672e1bd05d1d0fd7c52e07b6df2316e"],[0x2c6dc,48,"114ced485b82e81768a5aab41bef2642f07b0ca7497b5ec323f5952da6023358"],[0x2ae44,508,"c9630148521a1baf38cbcad8f3a19d8a758ae04a94a2b5c90fd8109b96cf251a"]]:
			if not Pure.signature(d,part[0],part[1],[],part[2]):
				d.fail("FE7 convoy","Changed convoy level or Light Rune cleanup helper."); return {}
		return {"op":"fe7_convoy_level","character":d.u8(at+46),"flag":d.u8(at+56)}
	if pointer&1 and helper == 0x79ed4 and Pure.actual_signature(d,at,48,[],"90e2ebca685dd2ee6c5b689cd8ef3bb22b318c97a2c31c96d91d2053e02c940a"):
		return {"op":"defeat"}
	if pointer&1 == 0 or not HELPERS.has(helper) or not Pure.actual_signature(d,at,HELPERS[helper][0],[],HELPERS[helper][1]):
		d.fail("FE7 native callback","Unsupported or changed helper at 0x%x." % pointer)
		return {}
	if helper == 0x7d94c and not Pure.signature(d,0x9f88c,124,[],"2aa215434009b3d07eeb6db88e843eacce01cc8adc473148ef586fc2c4362502"):
		d.fail("FE7 support archive","Changed native support archive helper."); return {}
	if helper == 0xb7070 and not (Pure.signature(d,0xdb10d4,80,[],"1209fb5878743f49e86258459694f099e8c3dd3b8920e844aa6ce36f71be8ad4") and Pure.signature(d,0xb6e40,560,[],"2370372c98ddd7a339ca92c19052d506d640bb785170aa06b50db96b36627339")):
		d.fail("FE7 scene process","Changed scene transition process."); return {}
	if helper == 0x7e658: return {"op":"scene_unit","action":"remove","character":d.u8(at+18)}
	if helper in [0x7e694,0x7e71c]: return {"op":"scene_unit","action":"visibility","character":d.u8(at+2),"hidden":helper == 0x7e694}
	if helper == 0x7b684 and (not Pure.signature(d,0x7b630,84,[],"7efde6803dad3636e0c569587ba99032a1cc96e75b8e92e4f6320a4ab6cfb9d8") or not Pure.signature(d,0xd6f81c,24,[],"9b60f4eca12ace1f9814b028ba388010ddf6eeb088615e0654a86d2c8c88028e")):
		d.fail("FE7 scene process","Changed vertical shake process."); return {}
	if helper in [0x7e378,0x7e3bc,0x7e444,0x7e4a4]:
		for part in [[0x7e340,56,"bcd035346f6b79a43140bf17a6a311c9bb57b79219e4425ba08f1e7240c83538"],[0xd837e8,16,"0e15d0f803cbb53a1fb54a5c6d0a2090f9b983e75e1afdb639c5a8e64bb4cb1a"],[0xd837f8,48,"06a2f64222c6e49363f1d3ccfb2dee88406339c236d13bf37a963ebad22ad574"],[0x7e3e8,92,"d543d1b7c5640eb7f651c2ebe78b568808e1b8104eba4f21b9f5614549256c61"]]:
			if not Pure.signature(d,part[0],part[1],[],part[2]):
				d.fail("FE7 scene process","Changed island scene display process."); return {}
	if helper == 0x7dfdc and not Pure.signature(d,0x1f208,88,[],"1fdd9869e72e8953006f3d5ecdd0d44c9577de3d598a1a932f82527dae2225eb"):
		d.fail("FE7 scene process","Changed magic-seal arrival display."); return {}
	if helper in [0x7cd60,0x7bc54,0x7bc68,0x7bc80,0x7bcd8,0x7bcec,0x7c1e8,0x7c1fc,0x7c210,0x7cd34,0x7cd48,0x7cd78]:
		for part in [[0x7b8e4,880,"6ca36ea51fb142c0afe3eedc2434b85c69ccba75847383ba1d68f3406a424842"],[0xd6f854,88,"b98bd4461a7e8c3c5de86c8455bce76819891d475a5c429ead77dd45ec1c923b"],[0x7bc94,68,"8b1a1a2d40c6c7a16599a7b0e533c6e8d0191d156208862863bfe13ae5c9ac77"],[0x7bd00,1320,"6351563b72a0f0ab4ebca0dbdfa661a4a0191089d88477d1a103a690f6950875"],[0xd6f8ac,176,"f5e5c22f013a58d32a2a06bc2288c2a350067fab3e4872e5085213ebd2c98460"],[0x7cab8,636,"70edd2abcc2bc833634546a1dd599a59fcd10725d33b48229bdc3b6b5d98221f"],[0xd6fa2c,152,"ba4fff3ccdc38d5b7684fe5e99d64559aa448b60729985488525a2c73e5eff47"]]:
			if not Pure.signature(d,part[0],part[1],[],part[2]):
				d.fail("FE7 scene process","Changed portal display process."); return {}
	if helper in [0x7b6c8,0x7b70c] and (not Pure.signature(d,0xd6f7ec,48,[],"12b123f2b63b6f787fb1239ddb88c03f3ce4ef8362e3553f81a2cabef6d9d88f") or not Pure.signature(d,0x7b578,184,[],"f045035934f025d5dbeb16f413d191a8ac6b91bf7732f80b8662a925c5e726a7")):
		d.fail("FE7 native callback","Changed screen shake process."); return {}
	if helper in [0x7b32c,0x7b2dc,0x18c20]: return {"op":"fe7_cleanup","heal":helper != 0x7b2dc}
	if helper == 0x7b24c: return {"op":"fe7_formation"}
	if helper == 0xb9270 and not Pure.actual_signature(d,d.ptr(at+16),176,[],"de37c5c934aea831810984f07efa62ec11ac8a427609d3907176b4847aa1c520"):
		d.fail("FE7 native callback","Changed ending-roll process."); return {}
	if helper == 0x7da3c:
		if not Pure.signature(d,0x7a0b4,20,[],"a6df465cfbda93d9dc231331271ece0c002246ebc0c6f5d9dcfa16fcf52ad23e"):
			d.fail("FE7 native callback","Changed native flag setter."); return {}
		return {"op":"set","flag":23}
	return {"op":"nop"}

static func predicate(d: RefCounted, pointer: int, chapter: int, lesson: bool = false) -> Dictionary:
	var at := (pointer-0x08000000)&~1
	var helper := Policy.identity(d,at)
	if pointer&1 and helper == 0x7cdec and Pure.actual_signature(d,at,20,[],"69793f9cb289e6caf0c002ec9f4355728ed0505c4c1fd6bd3bac5fcd6d6ad427"):
		# The port unlocks the ROM teaser on completion, without cartridge SRAM/link requirements.
		return {"kind":"constant","value":true}
	if pointer&1 and helper == 0x7ce00 and Pure.actual_signature(d,at,20,[],"2445b68d34db0b1ddd7071429c0ee210fdcec4fae9fcf9374db4062bf363dfe8"):
		# The port unlocks the ROM teaser on completion, without cartridge SRAM/link requirements.
		return {"kind":"constant","value":true}
	if pointer&1 and helper == 0x7a528 and Pure.actual_signature(d,at,60,[],"307b8855f4909cbac59460e9d00ab701caf140f096b35b78df94f7bfc57e6ad4"): return {"kind":"enemy_count_at_most","maximum":d.u8(at+42)}
	if pointer&1 and helper == 0x7eb9c and Pure.actual_signature(d,at,48,[],"baba7a986d37b985471bd1fd7f010199f5adbaf858d8dd6bc7f4639890b4b6b8"):
		return {"kind":"route_support_flag","route":d.u8(at+6),"support":predicate(d,0x08000001+Policy.address(d,0x7ac6c),chapter),"flag":d.u8(at+20)}
	if pointer&1 and helper == 0x7e908 and Pure.signature(d,0x7e908,44,[],"d7211edd5ac1ee187aeebb1250ddee9da669b160c30cb7ec689db4956a504e74") and Pure.signature(d,0x7ad78,20,[],"6a45984b0394e9d2638c2d6d16eb9b3a54e9e93ec8080d770e860ca60803f361"):
		return {"kind":"phase_terrain","phase":"enemy","x":((d.u16(at+20)>>6)&31),"y":((d.u16(at+18)>>6)&31),"terrain":d.u8(at+22)}
	if pointer&1 and helper == 0x7e950 and Pure.actual_signature(d,at,84,[56,57,58,59],"5fc67f152586827feb537152fe3922f352caf2a14a52b8a261cffb0be9705302"):
		var tiles: Array = []
		var table: int = d.ptr(at+56)
		if not d.require_range(table,20,"FE7 occupied tiles"): return {}
		for index in range(d.u8(at+68)+1): tiles.append([d.u8(table+index*2),d.u8(table+index*2+1)])
		return {"kind":"occupied_tiles","tiles":tiles,"faction":"player"}
	if pointer&1 and helper in [0x7a794,0x7a7a4] and ((Pure.signature(d,0x7a794,16,[],"735b21a42c506427e9bd006eb2ef302966e48ab7fcfc47ecf9845c737ca36a9c") and helper == 0x7a794) or (Pure.signature(d,0x7a7a4,16,[],"594c4659b87250bd0d545e2cb556be7237340a55e9ca6b5cf8317fcfae275384") and helper == 0x7a7a4)) and Pure.signature(d,0x7a754,64,[],"87be9926e77326bddc02a87ae5ea824597f5dd64cb05ea879daa5e2c2f9630fd"):
		return {"kind":"presence","character":d.u8(at+2),"factions":["player"],"deployed":true}
	if pointer&1 and helper == 0x7e774 and Pure.signature(d,0x7e774,48,[],"0cfc45b4c497a767a4b66963620c0a04e580f61332dc0d7031058e016cc2d416") and Pure.signature(d,0x7a794,16,[],"735b21a42c506427e9bd006eb2ef302966e48ab7fcfc47ecf9845c737ca36a9c") and Pure.signature(d,0x7a754,64,[],"87be9926e77326bddc02a87ae5ea824597f5dd64cb05ea879daa5e2c2f9630fd"):
		return {"kind":"unit_class_level","character":d.u8(at+2),"class_id":d.u8(at+24),"minimum":d.u8(at+32)+1}
	if pointer&1 and helper == 0x7e7a4 and Pure.signature(d,0x7e7a4,84,[],"f9cab3f356f40a771247bce90323d3897db939756459104f6ce09f6c058ea508"):
		return {"kind":"usable_weapon","character":d.u8(at+2)}
	if pointer&1 and helper == 0x7e7f8 and Pure.signature(d,0x7e7f8,36,[],"86e8b4d2b419fe320568f41a0acea70c04bded9a8f072bb6aa08638e5d2346e2"):
		return {"kind":"unit_corner","character":d.u8(at+2),"maximum_x":d.u8(at+14),"maximum_y":d.u8(at+22)}
	if pointer&1 and helper in [0x7e81c,0x7e838] and ((Pure.signature(d,0x7e81c,28,[],"d9b0dcf3f5786ece3d97a1f3b539d7eb1db23c4360391f9ab625f6f20993abf4") and helper == 0x7e81c) or (Pure.signature(d,0x7e838,28,[],"80fb37847557803ac323774ac8f1e4f6b486085744463b1b53a5f8d9cf51dde4") and helper == 0x7e838)) and Pure.signature(d,0x18e60,64,[],"3c7f0c3c92579f3e93a4e0cf138cd8a9b73c01d4a77ddd85f4785307f986041c"):
		return {"kind":"unit_hp_zero","character":d.u8(at+2)}
	if pointer&1 and helper in [0x7ac30,0x7ac44,0x7ac58,0x7ac6c,0x7ac80,0x7ac94] and Pure.call_target(d,at+6) == Policy.address(d,0x27090) and Pure.actual_signature(d,at,20,[2,4,6,7,8,9],"5cc27bf2160f2c70c35c299f029984cd2b629efca6c730b7454dabac0889f720") and Pure.signature(d,0x27090,48,[],"c3e78e9b0dd556e797f53cb7a4020c2393de613cfc37bbb2d6a266c13b38a36d"):
		return {"kind":"support_rank","first":d.u8(at+2),"second":d.u8(at+4),"minimum":d.u8(Policy.address(d,0x270b0))+1}
	if pointer&1 and helper == 0x7ae7c and Pure.signature(d,0x7ae7c,24,[],"0118757ac37699147b3a1ffd54ad15d1a164fa355e96296ec6e5be625d24bfe5") and Pure.signature(d,0x7aa24,56,[],"d0e00a8225ba0607bb772dc67317f29302d0be68cc5af98e1267e64e174fd9f1"):
		return {"kind":"enemy_count_at_least","minimum":d.u8(at+10)+1}
	if pointer&1 and helper == 0x7e540 and Pure.signature(d,0x7e540,52,[],"a0026c27bc1c71541fc7d3616f15f6ac4c847f9d4251a5afadd9b09edd7391e1") and Pure.signature(d,0x307e4,48,[],"a6f347b5852499433db5a0f1b972083d58579850367eb54329773f5d7d0b909e"):
		return {"kind":"battle_lord"}
	if pointer&1 and helper == 0x7fcc4 and Pure.signature(d,0x7fcc4,56,[],"f5d20c6a316f4ed5c6244b62b4286e35f7d9e4efd833f5f427d69e21183cf194"):
		return {"kind":"battle_any","characters":[1,2,d.u8(at+22)]}
	if pointer&1 and helper == 0x7fd34 and Pure.signature(d,0x7fd34,36,[],"0e8e29af29d881e517e55e785331d652fa33d1b4dfae50b9c80c7a794879efa8"):
		return {"kind":"battle_any","characters":[d.u8(at+12)]}
	if pointer&1 and helper == 0x7aea8 and Pure.actual_signature(d,at,28,[],"49c313f496d11baaf32e98659d3d954469a0c5e31f8a388d9de79ddd3f4a8c26") and Pure.signature(d,0x18e60,64,[],"3c7f0c3c92579f3e93a4e0cf138cd8a9b73c01d4a77ddd85f4785307f986041c"):
		return {"kind":"active_dead"}
	if pointer&1 and helper == 0x7e074 and Pure.actual_signature(d,at,28,[],"c6df0f15a76d71d36a905c3604a56ebac2ddec88c1d9d41a633ea86d52824d04") and Pure.signature(d,0x23d90,12,[],"575f318afea5e1f83a6f88a2ed7a8d33138d372740beff3ebc0e4b580d27ca49"):
		return {"kind":"funds","minimum":d.u32(at+24)+1}
	if pointer&1 and helper == 0x7e0a0 and Pure.actual_signature(d,at,36,[],"bee9e47f17ac81aa4370a788d453e2058465336e7700d4faeaa6e4948a475e42"):
		return {"kind":"flag_pair","set":d.u8(at+2),"clear":d.u8(at+14)}
	if pointer&1 and helper == 0x7e14c and Pure.actual_signature(d,at,44,[],"2c1e46fe6dded43075e29fa666eb89e38690eb617961331b664524e39b2c0a1d") and Pure.signature(d,0x7e0d4,120,[],"5c827d92613eb5df838e9e55bf6d9210357646adb087c63f00367e59be1fa9a7") and experience_getter(d):
		var sides: Array = []
		for operand in [at+28,at+32]:
			var ids: Array = []; var table: int = d.ptr(operand); var ended := false
			for index in range(64):
				var id: int = d.u16(table+index*2)
				if id == 0: ended = true; break
				if id > 255 or ids.has(id): break
				ids.append(id)
			if not ended or ids.is_empty(): d.fail("FE7 route","Invalid experience comparison roster."); return {}
			sides.append(ids)
		return {"kind":"experience_rosters","first":sides[0],"second":sides[1]}
	if pointer&1 and helper == 0x7e188 and Pure.actual_signature(d,at,60,[],"010219d404edbd2c882ff6de1c9a5ab2c1278664434e2fcd2938b4caff9cbada"):
		var flags: Array = []
		for offset in [2, 18, 32]: flags.append(d.u8(at+offset))
		return {"kind":"count","condition":{"flags":flags,"max":1}}
	if pointer&1 and helper == 0x7e1e8 and Pure.actual_signature(d,at,148,[],"2f09984770e5e43fca6d7e0432149f1cf98aa0d3583fdcc27f76caae2803b66b"):
		var flags: Array = []
		for offset in [2, 18, 32, 46, 60, 74, 88, 102, 116]: flags.append(d.u8(at+offset))
		return {"kind":"count","condition":{"flags":flags,"max":3}}
	if pointer&1 and helper == 0x7dec0 and Pure.actual_signature(d,at,60,[],"8434ba3bb4036017cfe1775d05e6d180b8f9512b525df492181df64d66fbc89f"):
		return {"kind":"desert_find","classes":[d.u8(at+18),d.u8(at+22)],"denominator":d.u8(at+30)}
	if pointer&1 and helper == 0x7df44 and Pure.actual_signature(d,at,68,[],"ce707e38ce38817f39644af9e8591fafe8cf8f29f654c542960ac29466ceaeb3") and experience_getter(d):
		return {"kind":"chapter_experience","minimum":d.u32(at+56)+1}
	if pointer&1 and helper == 0x7df88 and Pure.actual_signature(d,at,84,[],"4481a9b9ffd2835607863ac26d75862ba5dda15dc9a6b73a3d2317b21aecc114"):
		return {"kind":"combined_levels","characters":[1,2,d.u8(at+46)],"minimum":d.u8(at+66)+1}

	if pointer&1 and helper == 0x7dddc and Pure.actual_signature(d,at,44,[],"05ce44fbf3a4f6185453fba3721e7aa81502bfb1c05d1b5ac61a2f3db57b2c97"):
		return {"kind":"campaign_level_flag","character":d.u8(at+2),"minimum":d.u8(at+18)+1,"flag":d.u8(at+22)}
	if pointer&1 and helper == 0x7dd54 and Pure.actual_signature(d,at,48,[],"77d6b1d08636d44d6088403b69b6c3bd805f160ee6fbc44970d8e052d6fb7cb1"):
		# gBmMapUnit[8][3], then GetUnit(slot)->index affiliation bits.
		return {"kind":"occupied_tile","x":3,"y":8,"faction":"player"}
	if pointer&1 == 0 or not d.require_range(at,28,"FE7 predicate"):
		d.fail("FE7 condition","Invalid predicate pointer."); return {}
	if helper == 0x7ae6c and Pure.actual_signature(d,at,16,[],"1ec9b923cd50833284e092124e7d3f989dcbc7e477dc905a7e32953767a2c8bf") and Pure.signature(d,0x9f9f8,68,[],"032578b72cf8ac58c66519a16487afa2c86cc0f12d1364311d3961bc5d29973c"):
		# Native completed-save availability; the port has no GBA SRAM slots.
		return {"kind":"constant","value":false}
	if helper == 0x7ae2c and Pure.actual_signature(d,at,16,[],"5566a6a1df4a0fa8f2dc31f636c0c27e9ff161c7b6df36f52187a8fc73adcd2e"):
		# This bit enables the tactician: false skips the scene actor and
		# tactician-specific conversations. The port supplies a tactician.
		return {"kind":"constant","value":true}
	if helper in [0x7dd0c,0x7dd24,0x7dd3c]:
		var count: Variant = preload("res://runtime/rom_native_flags.gd").counter(d,pointer)
		return {} if count == null else {"kind":"count","condition":{"flags":count.flags,"max":count.threshold}}
	if helper == 0x7db8c and Pure.actual_signature(d,at,36,[],"8ee1a1e31453d055ad9acae90467abf33f4f696aa7fc18771835ddd3f3da1792"):
		return {"kind":"active_any","characters":[d.u8(at+8),d.u8(at+12),d.u8(at+16),d.u8(at+20)]}
	if helper == 0x7daf4 and Pure.actual_signature(d,at,44,[],"3eee402fc7efef96abcb69287cb5b0316da187917bbbd13280f8e2d846e59a23"):
		# gBmMapTerrain[y][x] differs from the destroyed-village tile,
		# and the native conversation flag is still clear.
		return {"kind":"unvisited_terrain","flag":d.u8(at+2),"x":(d.u16(at+26)>>6)&31,"y":(d.u16(at+22)>>6)&31,"excluded":d.u8(at+24)}
	if pointer&1 and Policy.identity(d,(pointer-0x08000000)&~1) == 0x7aa5c:
		if not rout(d,pointer): return {}
		return {"kind":"unit_count","faction":"enemy","maximum":0,"ready":false}
	if at+44 <= d.rom.size() and Pure.actual_signature(d,at,44,[2,32,33],"72e6683f08c5154810965538190a1257f9f81c9c3f02c578b2a25d5f810558a0") and Pure.signature(d,0x18124,60,[],"31c19774d98b7168ece7dbf1ce3092ef2f772eb69cee3ec6d2a7aa385c462cec"):
		return {"kind":"unit_at","character":d.u8(at+2),"faction":"player","x":d.u8(at+32),"y":d.u8(at+33)}
	if pointer&1 and helper == 0x7da28 and Pure.actual_signature(d,at,20,[],"9b4a62fcdf56c9dd28cbc324ddf6a52c414d7dc6ed2367c236dc0c71787f1c63") and Pure.signature(d,0x7aab0,60,[],"fc52b12b778ef095e52537926432bf3525760fa3224e6e781fc1b38aafd53217") and Pure.signature(d,0x190f4,20,[],"463e110a35659cdb745f6f8d65a835f2ea3bebf7eb54f9b38c0631b8fee38da0"):
		# At most one unacted, deployed, living player: optional Wait lesson.
		return {"kind":"unit_count","faction":"player","maximum":1,"ready":true}
	if at%4 == 0 and Pure.actual_signature(d,at,20,[6],"cf285a6a883703baa005a99bc11ebb59636576f920d0340ccda9e3623dab1c9a") and d.u8(at+6) < 67:
		return {"kind":"constant","value":chapter == d.u8(at+6)}
	for row in [["player","d95a7ff1efdae5568bef16a54baa6b2afb3ab3e5392596b7fcdf5d3eb30e0a0e"],["enemy","6a45984b0394e9d2638c2d6d16eb9b3a54e9e93ec8080d770e860ca60803f361"]]:
		if at%4 == 0 and Pure.actual_signature(d,at,20,[],row[1]): return {"kind":"phase","value":row[0]}
	if Pure.actual_signature(d,at,16,[2,4,5,6,7],Pure.WRAPPER):
		var search := Pure.call_target(d,at+4)
		if search >= 0 and Pure.actual_signature(d,search,48,[],"8b84a096aa10aac77b44a8f8e7b66f0444a6eb4e085a610942d324985770b11b") and Pure.signature(d,0x190f4,20,[],"463e110a35659cdb745f6f8d65a835f2ea3bebf7eb54f9b38c0631b8fee38da0"):
			return {"kind":"presence","character":d.u8(at+2),"factions":["player"],"include_dead":true}
		var query: Variant = Pure.describe(d,pointer,"fe7")
		if query == null:
			d.error.reason += " Callback 0x%x." % pointer
			return {}
		if int(query.excluded_state) == 4 and [int(query.first),int(query.last)] in [[1,63],[65,191]]:
			return {"kind":"presence","character":int(query.character),"factions":["player"] if int(query.first) == 1 else ["neutral","enemy"]}
		d.fail("FE7 condition","Unsupported native slot range or state mask."); return {}
	# GetUnitByCharId searches all slots, including casualties. Match the whole
	# wrapper and getter; decode only the character operand and call location.
	if Pure.actual_signature(d,at,28,[2,4,5,6,7],Pure.AFFILIATION):
		var getter := Pure.call_target(d,at+4)
		if getter >= 0 and Pure.actual_signature(d,getter,60,[],"31c19774d98b7168ece7dbf1ce3092ef2f772eb69cee3ec6d2a7aa385c462cec") and d.u8(at+2) > 0:
			# This wrapper asks whether the character joined the player slots,
			# even if dead. A removed/unrecruited character is not a member.
			return {"kind":"presence","character":d.u8(at+2),"factions":["player"],"include_dead":true}
	if lesson and tutorial_predicate(d,pointer): return {"kind":"constant","value":true}
	d.fail("FE7 condition","Unsupported or changed predicate at 0x%x." % pointer)
	return {}

static func rout(d: RefCounted, pointer: int) -> bool:
	if pointer&1 and Policy.identity(d,(pointer-0x08000000)&~1) == 0x7aa5c and Pure.signature(d,0x7aa5c,24,[],"d471743eee0399b05b016da96feeeac1446204125537dca7f3b51c0df6b54f96") and Pure.signature(d,0x7a9f0,52,[],"229d89af315d60983b729130ca3d84d31dba11791d48d731b9a70d015a035cc4"): return true
	d.fail("FE7 victory condition","Unsupported or changed rout predicate.")
	return false

static func chapter_predicate(d: RefCounted, pointer: int) -> int:
	var at := (pointer-0x08000000)&~1
	# Complete pure chapter-equality routine, including the chapter-state RAM
	# literal. Only CMP's chapter operand is variable. Supports repointed helpers
	# and changed chapter operands without trusting arbitrary native code.
	if pointer&1 and at%4 == 0 and Pure.actual_signature(d,at,20,[6],"cf285a6a883703baa005a99bc11ebb59636576f920d0340ccda9e3623dab1c9a") and d.u8(at+6) < 67: return d.u8(at+6)
	d.fail("FE7 condition","Unsupported or changed chapter predicate.")
	return -1

static func game_over(d: RefCounted, at: int) -> bool:
	# The engine owns defeat and its UI; recognize this complete native process
	# rather than silently discarding an arbitrary always-event callback.
	if Pure.actual_signature(d,at,80,[],"f0a15670b18b9ea9a160323510d61631861d91d0b520f4c8f747f6a888cacaad"): return true
	d.fail("FE7 game over","Changed native game-over program.",at)
	return false

static func tutorial_predicate(d: RefCounted, pointer: int) -> bool:
	# Reviewed checks for wait/trade/vulnerary menu choices. Any legal action
	# advances these optional lessons; they never force the native input.
	var predicates := {0x7af10:[20,"e7c573f5ca9218bb4768ddeaf63130e7d5803ce1214eca9297dbf6ab6725c576"],0x7d97c:[20,"59c58a0a56da4cb4c788cac0e79f828e8a512958c690c48e7a1628a3025e00f1"],0x7d990:[28,"09ed4edaf2116900320ca56123370617e078ac285cd0572d633089eb4202f700"],0x7d9ac:[60,"3faf95a75126ef60675ab0a747ac1d3fcab6b488254947a72e6e8fed7230721a"]}
	var at := (pointer-0x08000000)&~1
	var helper := Policy.identity(d,at)
	if pointer&1 and predicates.has(helper) and Pure.actual_signature(d,at,predicates[helper][0],[],predicates[helper][1]): return true
	d.fail("FE7 tutorial condition","Unsupported or changed input predicate at 0x%x." % pointer)
	return false

static func campaign(d: RefCounted) -> Dictionary:
	# Native tutorial-to-main-story conversion table, with full progress retained.
	if not Pure.signature(d,0x7fd9c,240,[76,77,78,79],"aad0a1ddfb605380bf760708d4b538a1cf70afb0cecf12df341c1e7347a37ea8") or not Pure.signature(d,0x7fd58,68,[],"23512515414c13f61d44f57a8e1e543aba9fd245b9c3694458bc24de7b14262d") or not Pure.signature(d,0x17574,40,[],"e3e81a1d2fdb5e21e62d37d15295292479a3e41940c965a3e845c3d20ed269da") or not Pure.signature(d,0x174a0,84,[48,49,50,51],"400ac305ff222d071b6b9995987ae9ca67913889564367bee12606f52dc22b8c") or not Pure.signature(d,0x174f4,128,[80,81,82,83],"d7848b6e253b8699d112e78256f8c7cf28237639d7c8265cfa1f1309838f31ab"):
		d.fail("FE7 campaign","Changed Lyn handoff or asset evaluation helper."); return {}
	var result := {"aliases":{},"clear_flags":[],"thresholds":[d.u32(Policy.address(d,0x7fd98)),d.u32(Policy.address(d,0x7fd7c)),d.u32(Policy.address(d,0x7fd80))],"flags":[d.u8(Policy.address(d,0x7fd72)),d.u8(Policy.address(d,0x7fd66))]}
	var table: int = d.ptr(Policy.address(d,0x7fde8))
	for index in range(64):
		var at := table+index*8
		if not d.require_range(at,8,"FE7 returning army"): return {}
		var source: int = d.u8(at); var target: int = d.u8(at+1)
		if source == 0: return result
		if target == 0 or result.aliases.has(target) or d.u16(at+2) != 0 or d.u32(at+4) > 164:
			d.fail("FE7 returning army","Invalid conversion row.",at); return {}
		result.aliases[target] = source
		if d.u32(at+4): result.clear_flags.append(d.u32(at+4))
	d.fail("FE7 returning army","Unterminated conversion table."); return {}

static func experience_getter(d: RefCounted) -> bool:
	if Pure.signature(d,0xa0ba8,52,[],"527a91432bbc883998dedf0988b8a031772ce312ce45fa9b53fe081e1bc43948") and Pure.signature(d,0xa0a68,96,[],"0ccd50c6c7324b5f77fe0fd23f87dc9a60d0b9681126b3ebd6792f41a1231b88"): return true
	d.fail("FE7 experience","Changed native experience record query or accumulation."); return false

