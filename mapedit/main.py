#!/usr/bin/env python3
"""
DOOM 2D Atari - Map Editor
Usage: python mapedit/main.py [mapfile.map]
"""

import sys
import os
import tkinter as tk

# Ensure project root is in path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from mapedit.editor import MapEditor


def main():
    root = tk.Tk()
    root.geometry("1400x800")
    root.configure(bg='#111')

    filename = None
    if len(sys.argv) > 1:
        filename = sys.argv[1]

    editor = MapEditor(root, filename)
    root.mainloop()


if __name__ == '__main__':
    main()
