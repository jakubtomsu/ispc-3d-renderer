# ISPC 3D Renderer
A simple and tiny software triangle rasterizer written with C/C++ and [Intel's ISPC](https://ispc.github.io/index.html).
I haven't done any major optimizations, it's a toy project just to learn about 3d graphics and ISPC.

The program renders an image on the CPU, which then gets displayed on a screen with OpenGL.

Depends on [GLFW](https://glfw.org) and [GLAD](https://glad.dav1d.de/) for platform-specific code and OpenGL.

The "driver" code is in [main.cpp](main.cpp) and the actual rendering is in [renderer.ispc](renderer.ispc)

<p>
<img src="screenshots/swordfish.png" width=45%>  
<img src="screenshots/swordfish_w.png" width=45%>  
</p>
<p>
<img src="screenshots/wattson.png" width=45%>  
<img src="screenshots/wattson_w.png" width=45%>  
</p>
<p>
<img src="screenshots/bunny_teapot.png" width=45%>  
<img src="screenshots/bunny_teapot_w.png" width=45%>  
</p>