extends RefCounted
## Identification des manettes (vendor/product extraits du GUID SDL).

const SONY := "054c"
const MICROSOFT := "045e"
const NINTENDO := "057e"
const VALVE := "28de"


static func identify(device: int) -> Dictionary:
	var name := Input.get_joy_name(device)
	var guid := Input.get_joy_guid(device)
	var vendor := ""
	var product := ""
	# GUID SDL : octets 4-5 = vendor, 8-9 = product, en little-endian
	if guid.length() >= 20 and guid.is_valid_hex_number():
		vendor = (guid.substr(10, 2) + guid.substr(8, 2)).to_lower()
		product = (guid.substr(18, 2) + guid.substr(16, 2)).to_lower()
	var lower := name.to_lower()
	var fam := "generic"
	var label := name if name != "" else "Manette"
	if vendor == SONY:
		match product:
			"0ce6": fam = "dualsense"; label = "DualSense"
			"0df2": fam = "dualsense"; label = "DualSense Edge"
			"05c4", "09cc", "0ba0": fam = "ds4"; label = "DualShock 4"
			"0268": fam = "ds3"; label = "DualShock 3"
			_: fam = "ds4"; label = "Manette PlayStation"
	elif vendor == MICROSOFT:
		fam = "xbox"
		label = "Manette Xbox 360" if product in ["028e", "028f", "0719"] else "Manette Xbox"
		if product in ["028e", "028f", "0719"]: fam = "xbox360"
	elif vendor == NINTENDO:
		fam = "switch"; label = "Manette Pro Switch" if product == "2009" else "Joy-Con"
	elif vendor == VALVE:
		fam = "steam"; label = "Steam Deck" if product == "1205" else "Steam Controller"
	elif "dualsense" in lower or "ps5" in lower:
		fam = "dualsense"; label = "DualSense"
	elif "ps4" in lower or "dualshock" in lower or "wireless controller" in lower:
		fam = "ds4"; label = "DualShock 4"
	elif "xbox" in lower or "xinput" in lower:
		fam = "xbox"; label = "Manette Xbox"
	elif "nintendo" in lower or "pro controller" in lower:
		fam = "switch"; label = "Manette Pro Switch"
	return {"device": device, "family": fam, "name": label, "vendor": vendor, "product": product}


static func connected() -> Array:
	var out := []
	for d in Input.get_connected_joypads():
		out.append(identify(d))
	return out


static func glyph_style(fam: String) -> String:
	match fam:
		"ds4", "dualsense", "ds3": return "ps"
		"xbox", "xbox360", "steam": return "xbox"
		"switch": return "nintendo"
		"keyboard": return "keyboard"
	return "xbox"


static func home_button_name(fam: String) -> String:
	match glyph_style(fam):
		"ps": return "PS"
		"xbox": return "Xbox"
		"nintendo": return "HOME"
	return "central"
