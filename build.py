import os
import subprocess

def runCmd(cmd):
    res = subprocess.run(cmd)
    if res.returncode != 0: exit(1)

def main():
	print("Building...")
	runCmd("ispc renderer.ispc -h renderer_ispc.h -o renderer_ispc.obj -O2")
	runCmd("cl main.cpp renderer_ispc.obj /I./ /MD /O2 /link user32.lib kernel32.lib gdi32.lib opengl32.lib msvcrt.lib shell32.lib glfw3.lib /LIBPATH:glfw/lib-vc2022")
	
if __name__ == "__main__": main()