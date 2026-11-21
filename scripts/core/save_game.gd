extends Node
## Player progression: wallet, unlocked gear, records. Persisted to user://save.json.

signal changed

const PATH := "user://save.json"

var wallet := 0
var weapons: Array = ["varg308"]
var gear: Array = []
var equipped := "varg308"
var highscores: Array = []     # [{score, date, moose, longest, best}]
var stats := {
	"hunts": 0, "moose": 0, "shots": 0, "hits": 0,
	"longest_shot": 0.0, "best_kill": 0, "total_earned": 0, "trophies": 0,
}

func _ready() -> void:
	load_game()

func owns_weapon(id: String) -> bool:
	return weapons.has(id)

func owns_gear(id: String) -> bool:
	return gear.has(id)

func buy_weapon(id: String, cost: int) -> bool:
	if owns_weapon(id) or wallet < cost:
		return false
	wallet -= cost
	weapons.append(id)
	save_game()
	return true

func buy_gear(id: String, cost: int) -> bool:
	if owns_gear(id) or wallet < cost:
		return false
	wallet -= cost
	gear.append(id)
	save_game()
	return true

func equip(id: String) -> void:
	if owns_weapon(id):
		equipped = id
		save_game()

## Records a finished hunt. Returns the 1-based rank on the high score table, or 0.
func submit_hunt(score: int, moose: int, longest: float, best: int, shots: int, hits: int) -> int:
	stats["hunts"] += 1
	stats["moose"] += moose
	stats["shots"] += shots
	stats["hits"] += hits
	stats["longest_shot"] = maxf(float(stats["longest_shot"]), longest)
	stats["best_kill"] = maxi(int(stats["best_kill"]), best)
	stats["total_earned"] += score
	wallet += score
	var rank := 0
	if score > 0:
		var entry := {
			"score": score, "moose": moose, "longest": longest, "best": best,
			"date": Time.get_date_string_from_system(),
		}
		highscores.append(entry)
		highscores.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
		rank = highscores.find(entry) + 1
		if highscores.size() > 10:
			highscores.resize(10)
		if rank > 10:
			rank = 0
	save_game()
	return rank

func best_score() -> int:
	return int(highscores[0]["score"]) if highscores.size() > 0 else 0

func reset_progress() -> void:
	wallet = 0
	weapons = ["varg308"]
	gear = []
	equipped = "varg308"
	highscores = []
	for k in stats:
		stats[k] = 0
	save_game()

func save_game() -> void:
	changed.emit()
	if G.no_save:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": 1, "wallet": wallet, "weapons": weapons, "gear": gear,
		"equipped": equipped, "highscores": highscores, "stats": stats,
	}, "\t"))

func load_game() -> void:
	if G.test_mode != "" and not G.args.has("usesave"):
		if G.args.has("rich"):
			wallet = 99999
		if G.args.has("allgear"):
			weapons = ["varg308", "finnskog4570", "storm93", "tordenskjold", "nordlys300"]
			gear = ["binoculars", "rangefinder", "call", "boots"]
		if G.args.has("weapon"):
			equipped = G.args["weapon"]
			if not weapons.has(equipped):
				weapons.append(equipped)
		return
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	wallet = int(d.get("wallet", 0))
	weapons = d.get("weapons", weapons)
	gear = d.get("gear", gear)
	equipped = d.get("equipped", equipped)
	highscores = d.get("highscores", [])
	var st = d.get("stats", {})
	for k in stats:
		if st.has(k):
			stats[k] = st[k]
	if not weapons.has("varg308"):
		weapons.append("varg308")
	if not weapons.has(equipped):
		equipped = "varg308"
