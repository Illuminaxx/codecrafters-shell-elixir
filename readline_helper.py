#!/usr/bin/env python3
import readline
import sys

builtins = ["echo", "exit", "type", "pwd", "cd"]

def completer(text, state):
    # Ne compléter que si c'est le premier mot (pas d'espace avant)
    line = readline.get_line_buffer()
    if " " not in line:
        matches = [cmd + " " for cmd in builtins if cmd.startswith(text)]
        return matches[state] if state < len(matches) else None
    return None

readline.set_completer(completer)
readline.parse_and_bind("tab: complete")

# Désactiver l'affichage des complétions multiples
readline.set_completion_display_matches_hook(lambda *args: None)

try:
    while True:
        line = input("$ ")
        # Envoyer la commande sur stdout pour que le parent la lise
        print(line, flush=True)
except EOFError:
    pass