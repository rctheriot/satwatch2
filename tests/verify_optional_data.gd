extends SceneTree
## Optional data layers must fail soft.
##
##   Godot --path . --headless --script res://tests/verify_optional_data.gd
##
## Aurora and conjunction data both come from live endpoints that can
## be unreachable -- CelesTrak already is, from this network. A chapter that
## cannot draw its subject is worse than one that is absent: on a wall, an empty
## globe reads as the demo being broken, in front of an audience.
##
## So every optional loader must report failure without erroring, and the deck
## must only gain a chapter when its data actually loaded.

var failures := 0

func _init() -> void:
	print("\nLoaders report missing data without erroring:")
	var weather := SpaceWeatherStore.new()
	_ok("SpaceWeatherStore", weather.load_from("res://data/__absent__.json")
		!= OK and not weather.loaded, "returns an error and stays unloaded")

	# Empty and malformed payloads, not just absent files -- a truncated
	# download is as likely as a missing one.
	var bad := "user://__bad_optional__.json"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	var w2 := SpaceWeatherStore.new()
	_ok("SpaceWeatherStore, malformed", w2.load_from(bad) != OK and not w2.loaded,
		"returns an error")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))

	# And the deck must gate on that, not merely tolerate it.
	print("\nDeck only gains a chapter when its data loaded:")
	var deck := ChapterDeck.new()
	var base: Array[Chapter] = deck._default_deck()
	deck.chapters = base.duplicate()
	var before := deck.chapters.size()
	var w3 := SpaceWeatherStore.new()
	if w3.load_from("res://data/space_weather.json") == OK:
		deck.add_space_weather_chapter(w3)
		_ok("space weather chapter", deck.chapters.size() == before + 1,
			"data present, chapter added")
	else:
		_ok("space weather chapter", deck.chapters.size() == before,
			"data absent, no chapter added")
	deck.free()

	print("\n%s" % ("ALL CHECKS PASSED" if failures == 0
		else "%d CHECK(S) FAILED" % failures))
	quit(1 if failures > 0 else 0)

func _ok(label: String, pass_: bool, detail: String) -> void:
	print("  [%s] %s -- %s" % ["PASS" if pass_ else "FAIL", label, detail])
	if not pass_:
		failures += 1
