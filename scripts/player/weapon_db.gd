class_name WeaponDB
extends RefCounted
## Rifles and equipment: stats, prices, descriptions.

const ORDER := ["varg308", "finnskog4570", "storm93", "tordenskjold", "nordlys300"]

const DATA := {
	"varg308": {
		"name": "Varg .308", "kind": "Bolt-action",
		"desc": "The rifle every Nordic hunter starts with. Honest, accurate and forgiving.",
		"type": "bolt", "cost": 0,
		"damage": 80.0, "velocity": 820.0, "drag": 0.0010, "mag": 5,
		"cycle": 1.1, "reload": 2.5, "recoil": 2.6, "sway": 1.0,
		"sound": "shot_308", "sight": "scope", "zooms": [3.0, 4.5, 6.0], "zero": 100.0, "ads_time": 0.24,
	},
	"finnskog4570": {
		"name": "Finnskog .45-70", "kind": "Lever-action",
		"desc": "Fast, heavy-hitting brush gun with open sights. The bullet drops like a stone past 150 m.",
		"type": "lever", "cost": 2500,
		"damage": 98.0, "velocity": 560.0, "drag": 0.0016, "mag": 6,
		"cycle": 0.62, "reload": 0.55, "recoil": 3.4, "sway": 1.15,
		"sound": "shot_4570", "sight": "iron", "zooms": [1.35], "zero": 75.0, "ads_time": 0.18,
	},
	"storm93": {
		"name": "Storm 9.3 Auto", "kind": "Semi-automatic",
		"desc": "Self-loading driven-hunt rifle with a red dot. Follow-up shots as fast as you can pull.",
		"type": "semi", "cost": 6000,
		"damage": 90.0, "velocity": 740.0, "drag": 0.0011, "mag": 4,
		"cycle": 0.24, "reload": 2.3, "recoil": 3.0, "sway": 1.1,
		"sound": "shot_93", "sight": "reddot", "zooms": [1.6], "zero": 100.0, "ads_time": 0.17,
	},
	"tordenskjold": {
		"name": "Tordenskjold .470", "kind": "Double rifle",
		"desc": "Two barrels of thunder. Drops anything it touches - if you can ride out the recoil.",
		"type": "double", "cost": 9500,
		"damage": 155.0, "velocity": 650.0, "drag": 0.0012, "mag": 2,
		"cycle": 0.28, "reload": 2.8, "recoil": 6.0, "sway": 1.25,
		"sound": "shot_470", "sight": "iron", "zooms": [1.3], "zero": 60.0, "ads_time": 0.2,
	},
	"nordlys300": {
		"name": "Nordlys .300 Magnum", "kind": "Long-range bolt-action",
		"desc": "Heavy barrel, flat trajectory and a 4-16x scope. Built for the shot across the lake.",
		"type": "bolt", "cost": 14000,
		"damage": 112.0, "velocity": 960.0, "drag": 0.0008, "mag": 4,
		"cycle": 1.3, "reload": 2.7, "recoil": 3.9, "sway": 0.8,
		"sound": "shot_300", "sight": "scope", "zooms": [4.0, 8.0, 12.0, 16.0], "zero": 200.0, "ads_time": 0.3,
		"variant": "magnum",
	},
}

const GEAR_ORDER := ["binoculars", "rangefinder", "call", "boots", "dog"]

const GEAR := {
	"binoculars": {"name": "Binoculars 8x42", "desc": "Hold B to glass distant shores and bogs.", "cost": 800},
	"rangefinder": {"name": "Laser Rangefinder", "desc": "Shows the distance to whatever you aim at through scope or binoculars.", "cost": 1800},
	"call": {"name": "Birch-bark Moose Call", "desc": "Press V to call. Bulls within earshot come looking.", "cost": 3200},
	"boots": {"name": "Felt-sole Boots", "desc": "Softer footsteps: moose hear you from much closer.", "cost": 4500},
	"dog": {"name": "Grey Elkhound", "desc": "Fant, a grey Norwegian elkhound with a GPS collar. Press G to let him loose: he ranges out into the wind, finds moose by scent or on their tracks, and holds them at bay, barking, while you close in under cover of the noise - or follows a runner until it stands. G again whistles him in. The compass and the map show where he is.", "cost": 7500},
}

static func get_weapon(id: String) -> Dictionary:
	return DATA.get(id, DATA["varg308"])

## Normalised 0..1 bars for the gear screen.
static func bars(id: String) -> Dictionary:
	var w: Dictionary = get_weapon(id)
	return {
		"Power": clampf(float(w["damage"]) / 160.0, 0.0, 1.0),
		"Velocity": clampf((float(w["velocity"]) - 400.0) / 600.0, 0.0, 1.0),
		"Fire rate": clampf(1.0 - (float(w["cycle"]) - 0.2) / 1.3, 0.05, 1.0),
		"Handling": clampf(1.0 - (float(w["recoil"]) - 2.0) / 5.0, 0.05, 1.0),
		"Optics": clampf(float((w["zooms"] as Array)[-1]) / 16.0, 0.05, 1.0),
	}
