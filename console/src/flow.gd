extends RefCounted
## Enchaînement de l'onboarding : manette → réseau → installation → comptes → affichage → terminé.


static func next(from: String) -> void:
	match from:
		"network":
			# L'installation n'a de sens que depuis la clé USB (ou en dev, en simulation).
			if App.info.get("mode", "dev") == "installed":
				next("install")
			else:
				App.push(load("res://src/screens/install.gd").new(func(): next("install")))
		"install":
			App.push(load("res://src/screens/accounts.gd").new(true, func(): next("accounts")))
		"accounts":
			App.push(load("res://src/screens/display.gd").new(func(): next("display")))
		"display":
			App.push(load("res://src/screens/done.gd").new())
