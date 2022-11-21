import os

def main():
	print("Building...")
	# os.system("ispc renderer.ispc")
	os.system("cl main.cpp /I./ /MD /O2 /link user32.lib kernel32.lib gdi32.lib opengl32.lib msvcrt.lib shell32.lib glfw3.lib /LIBPATH:glfw/lib-vc2022")
	
if __name__ == "__main__":
	main()