#!/usr/bin/env python3
"""Imprime brilho medio (0-255) de um PNG lido da stdin."""
import sys
from PIL import Image, ImageStat

im = Image.open(sys.stdin.buffer).convert("L")
print("%.3f" % ImageStat.Stat(im).mean[0])