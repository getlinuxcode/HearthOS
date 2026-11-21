#!/usr/bin/env bash
# Compile tous les scripts Godot de l'interface et affiche les erreurs.
cd "$(dirname "$0")/../console"
G=../tools/godot/Godot_v4.7.2-stable_win64_console.exe
"$G" --headless --path . --import >/dev/null 2>&1
"$G" --headless --path . tools/check.tscn 2>&1 | grep -E 'KO |CHECK|Parse Error|Compile Error|at: GDScript'
