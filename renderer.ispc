#include "common.h"

// https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/
// https://fgiesen.wordpress.com/2013/02/10/optimizing-the-basic-rasterizer/
// https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/perspective-correct-interpolation-vertex-attributes

static inline uniform int minInt3(uniform const int x,uniform const int y,uniform const int z) {
    return min(x, min(y, z));
}

static inline uniform int maxInt3(uniform const int x,uniform const int y,uniform const int z) {
    return max(x, max(y, z));
}

static inline uniform int orient2d(uniform const int<2>& a,uniform const int<2>& b,uniform const int<2>& c) {
    return (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x);
}

static inline uniform float edgeFunc(uniform const float<3>& a,uniform const float<3>& b,uniform const float<3>& c) {
    return (c[0] - a[0]) * (b[1] - a[1]) - (c[1] - a[1]) * (b[0] - a[0]);
}

static inline void addColorToPixel(uniform uint8 framebufferColor[], const int frameSizeX, const int x, const int y, const uint8<3> color) {
    const int index = (x + y * frameSizeX) * FRAMEBUFFER_COLOR_BYTES;
    framebufferColor[index + 0] = clamp((int)framebufferColor[index + 0] + color.r, 0, 255);
    framebufferColor[index + 1] = clamp((int)framebufferColor[index + 1] + color.g, 0, 255);
    framebufferColor[index + 2] = clamp((int)framebufferColor[index + 2] + color.b, 0, 255);
}

void drawDebugLine(uniform uint8 framebufferColor[],
              const int frameSizeX, const int frameSizeY,
              int ax, int ay, int bx, int by,
              const uint8<3> color) {
    int xdiff = bx - ax;
	int ydiff = by - ay;

	if(xdiff == 0 && ydiff == 0) {
		return;
	}
    
	if(abs(xdiff) > abs(ydiff)) {
		int xmin, xmax;
		// set xmin to the lower x value given
		// and xmax to the higher value
		if(ax < bx) {
			xmin = ax;
			xmax = bx;
		} else {
			xmin = bx;
			xmax = ax;
		}
        
        xmin = max(0, xmin);
        xmax = min(frameSizeX-1, xmax);

		// draw line in terms of y slope
		const float slope = (float)ydiff / (float)xdiff;
		for(int x = xmin; x <= xmax; x++) {
			int y = ay + (int)((float)(x - ax) * slope);
            if(y >= 0 && y < frameSizeY) {
			    addColorToPixel(framebufferColor, frameSizeX, x, y, color);
            }
		}
	} else {
		int ymin, ymax;
		// set ymin to the lower y value given
		// and ymax to the higher value
		if(ay < by) {
			ymin = ay;
			ymax = by;
		} else {
			ymin = by;
			ymax = ay;
		}

        ymin = max(0, ymin);
        ymax = min(frameSizeY-1, ymax);

		// draw line in terms of x slope
		const float slope = (float)xdiff / (float)ydiff;
		for(int y = ymin; y <= ymax; y++) {
			int x = ax + (int)((float)(y - ay) * slope);
            if(x >= 0 && x < frameSizeX) {
			    addColorToPixel(framebufferColor, frameSizeX, x, y, color);
            }
		}
	}
}

struct Edge {
    varying int oneStepX;
    uniform int oneStepY;
    varying int valueX;
};

static uniform Edge initEdge(uniform const int<2>& v0, uniform const int<2>& v1, uniform const int<2>& origin) {
    // Edge setup
    uniform const int a = v0.y - v1.y;
    uniform const int b = v1.x - v0.x;
    uniform const int c = v0.x * v1.y - v0.y * v1.x;
    
    // Step deltas
    uniform Edge result;
    result.oneStepX = a * programCount;
    result.oneStepY = b;
    
    // Initial pixel block x/y values
    varying const int x = origin.x + programIndex;
    varying const int y = origin.y;
    
    result.valueX = a * x + b * y + c;
    
    return result;
}

static uniform int<2> transformToPixelCoord(uniform const float<2> p, uniform const int frameSizeX, uniform const int frameSizeY) {
    uniform int<2> result = {
        (p.x * 0.5f + 0.5f) * frameSizeX,
        (p.y * 0.5f + 0.5f) * frameSizeY,
    };
    
    return result;
}

static float dot(const float<3> a, const float<3> b) {
    const float<3> temp = a * b;
    return temp.x + temp.y + temp.z;
}

static uniform float dot(uniform const float<3> a, uniform const float<3> b) {
    uniform const float<3> temp = a * b;
    return temp.x + temp.y + temp.z;
}

static uniform float<3> cross(uniform const float<3>& a, uniform const float<3>& b) {
    uniform const float<3> result = {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    };
    return result;
}

static float<3> lerp(const float<3> a, const float<3> b, const float t) {
    return (1.0f - t) * a + t * b;
}

static float length(float<3> a) {
    a *= a;
    return sqrt(a.x + a.y + a.z);
}

static float<3> normalize(const float<3> a) {
    return a / length(a);
}


// Main function for rendering the frame.
export void renderFrame(uniform uint8 framebufferColor[],
                        uniform uint16 framebufferDepth[],
                        uniform const int frameSizeX, uniform const int frameSizeY,
                        uniform const float pointData[], uniform const int pointNum,
                        uniform const float transformMat4[4][4],
                        uniform const float cameraX, uniform const float cameraY, uniform const float cameraZ,
                        uniform const bool enableWireframe) {
    memset(framebufferColor, 42, frameSizeX * frameSizeY * FRAMEBUFFER_COLOR_BYTES);
    memset(framebufferDepth, 0xff, frameSizeX * frameSizeY * FRAMEBUFFER_DEPTH_BYTES);

    if(enableWireframe) {
        // Render Geometry
        for(uniform int pointIndex = 0; pointIndex < pointNum; pointIndex += VERTEX_FLOATS * 3) {
            // Load vertex data
            uniform float<4> positions[3] = {
                {pointData[pointIndex + 0], pointData[pointIndex + 1], pointData[pointIndex + 2], 1.0f},
                {pointData[pointIndex + 6], pointData[pointIndex + 7], pointData[pointIndex + 8], 1.0f},
                {pointData[pointIndex + 12], pointData[pointIndex + 13], pointData[pointIndex + 14], 1.0f},
            };
    
            uniform float<4> transformedPositions[3] = {0};
            varying bool shouldSkipTriangle = false;

            foreach(v = 0 ... 3, row = 0 ... 4) {
                float sum = 0.0f;
                for(int col = 0; col < 4; col++) {
                    sum += transformMat4[col][row] * positions[v][col];
                }
                transformedPositions[v][row] = sum;
                shouldSkipTriangle |= transformedPositions[v].z < 0.0f;
            }
            
            if(any(shouldSkipTriangle)) goto wireframeEnd;
            
            foreach(v = 0 ... 3, e = 0 ... 3) {
                transformedPositions[v][e] /= transformedPositions[v].w;
            }
            
            // Transform into pixel positions
            uniform const int<2> v0 = transformToPixelCoord(transformedPositions[0].xy, frameSizeX, frameSizeY);
            uniform const int<2> v1 = transformToPixelCoord(transformedPositions[1].xy, frameSizeX, frameSizeY);
            uniform const int<2> v2 = transformToPixelCoord(transformedPositions[2].xy, frameSizeX, frameSizeY);
        
            const uint8<3> triLineCol = {2, 20, 5};
            drawDebugLine(framebufferColor, frameSizeX, frameSizeY, v0.x, v0.y, v1.x, v1.y, triLineCol);
            drawDebugLine(framebufferColor, frameSizeX, frameSizeY, v1.x, v1.y, v2.x, v2.y, triLineCol);
            drawDebugLine(framebufferColor, frameSizeX, frameSizeY, v2.x, v2.y, v0.x, v0.y, triLineCol);
            
            wireframeEnd:;
        }

    } else {
            
        uniform const float<3> sunDir = {0.707, 0.707, 0};
        uniform const float<3> sunCol = {1.64,1.27,0.99};
        uniform const float<3> skyCol = {0.16,0.20,0.28};
        uniform const float<3> indirectCol = {0.40,0.28,0.20};
        uniform const float<3> cam = {cameraX, cameraY, cameraZ};
        //uniform const float<3> diffuseCol = {0.85f, 0.1f, 0.3f};
        uniform const float<3> diffuseCol = {0, 1.0f, 0.8f};

        // Render Geometry
        for(uniform int pointIndex = 0; pointIndex < pointNum; pointIndex += VERTEX_FLOATS * 3) {
            // Load vertex positions
            uniform float<4> positions[3] = {
                {pointData[pointIndex + 0], pointData[pointIndex + 1], pointData[pointIndex + 2], 1.0f},
                {pointData[pointIndex + 6], pointData[pointIndex + 7], pointData[pointIndex + 8], 1.0f},
                {pointData[pointIndex + 12], pointData[pointIndex + 13], pointData[pointIndex + 14], 1.0f},
            };
            
            // Backface culling
            if(dot(cam - positions[0].xyz,
                   cross(positions[1].xyz - positions[0].xyz,
                         positions[2].xyz - positions[0].xyz)) < 0.0f) {
                goto triangleEnd;
            }
    
            uniform float<4> transformedPositions[3] = {0};
            uniform float<3> screenPositonClipZ;
            varying bool shouldSkipTriangle = false;

            foreach(v = 0 ... 3, row = 0 ... 4) {
                float sum = 0.0f;
                for(int col = 0; col < 4; col++) {
                    sum += transformMat4[col][row] * positions[v][col];
                }
                transformedPositions[v][row] = sum;
                shouldSkipTriangle |= transformedPositions[v].z < 0.0f;
            }
            
            if(any(shouldSkipTriangle)) goto triangleEnd;
            
            foreach(v = 0 ... 3) {
                screenPositonClipZ[v] = transformedPositions[v].z;
            }
            
            foreach(v = 0 ... 3, e = 0 ... 3) {
                transformedPositions[v][e] /= transformedPositions[v].w;
            }
            
            // Transform into pixel positions
            uniform const int<2> v0 = transformToPixelCoord(transformedPositions[0].xy, frameSizeX, frameSizeY);
            uniform const int<2> v1 = transformToPixelCoord(transformedPositions[1].xy, frameSizeX, frameSizeY);
            uniform const int<2> v2 = transformToPixelCoord(transformedPositions[2].xy, frameSizeX, frameSizeY);
    
            // Compute triangle bounding box
            uniform const int<2> bbMin = {
                max(0, minInt3(v0.x, v1.x, v2.x)),
                max(0, minInt3(v0.y, v1.y, v2.y)),
            };
            uniform const int<2> bbMax = {
                min(frameSizeX - 1, maxInt3(v0.x, v1.x, v2.x)),
                min(frameSizeY - 1, maxInt3(v0.y, v1.y, v2.y)),
            };
    
            uniform const float area = edgeFunc(positions[0].xyz, positions[1].xyz, positions[2].xyz);
            
            uniform const float screenPosInvZ0 = 1.0f / screenPositonClipZ[0];
            uniform const float screenPosInvZ1 = 1.0f / screenPositonClipZ[1];
            uniform const float screenPosInvZ2 = 1.0f / screenPositonClipZ[2];
            
            // Load vertex normals
            uniform float<3> normals[3] = {
                {pointData[pointIndex + 3], pointData[pointIndex + 4], pointData[pointIndex + 5]},
                {pointData[pointIndex + 9], pointData[pointIndex + 10], pointData[pointIndex + 11]},
                {pointData[pointIndex + 15], pointData[pointIndex + 16], pointData[pointIndex + 17]},
            };
            
            normals[0] *= screenPosInvZ0;
            normals[1] *= screenPosInvZ1;
            normals[2] *= screenPosInvZ2;
            
            positions[0] *= screenPosInvZ0;
            positions[1] *= screenPosInvZ1;
            positions[2] *= screenPosInvZ2;
            
            // Barycentric coordinates at bbMin corner
            uniform Edge edge0 = initEdge(v1, v2, bbMin);
            uniform Edge edge1 = initEdge(v2, v0, bbMin);
            uniform Edge edge2 = initEdge(v0, v1, bbMin);
                    
            for(uniform int y = bbMin.y; y < bbMax.y; y++) {
                // Barycentric coords at start of the row
                varying int w0 = edge0.valueX;
                varying int w1 = edge1.valueX;
                varying int w2 = edge2.valueX;
                
                // for(uniform int x = bbMin.x; x <= bbMax.x; x++) {
                foreach(x = bbMin.x ... bbMax.x) {
                    // If 'p' is on or inside all edges, render the pixel
                    if((w0 | w1 | w2) >= 0) {
                        const float w0a = (float)w0 / area;
                        const float w1a = (float)w1 / area;
                        const float w2a = (float)w2 / area;
                        const float oneOverZ = w0a * screenPosInvZ0 + w1a * screenPosInvZ1 + w2a * screenPosInvZ2;
                        const float z = 1.0f / oneOverZ;
                        // Interpolate the depth
                        const float depth = 
                            (w0a * screenPositonClipZ[0] +
                            w1a * screenPositonClipZ[1] +
                            w2a * screenPositonClipZ[2]) * z;
    
                        if(depth > 0.0f) {
                            const int index = x + y * frameSizeX;
                            const uint16 prevDepth = framebufferDepth[index];
                            // Note: the sqrt is a hack. I'm not really sure how to encode the depth
                            // properly, but linear is definitely not the right way.
                            const uint16 depth16 = (int)(sqrt(depth) * 2000.0f);
                            if(depth16 < prevDepth) {
                                framebufferDepth[index] = depth16;
    
                                const float<3> normal = (w0a * normals[0] + w1a * normals[1] + w2a * normals[2]) * z;
                                const float<3> position = (w0a * positions[0].xyz + w1a * positions[1].xyz + w2a * positions[2].xyz) * z;
    
                                const float<3> viewDir = normalize(cam - position);
                                
                                // Compute the pixel color
                                float<3> color = diffuseCol;
                                #if 1
                                const float<3> sun = max(dot(normal, sunDir), 0.0) * sunCol;
                                const float<3> sky = clamp(0.5 + 0.5 * normal.y, 0.0, 1.0) * skyCol;
                                const float<3> indirectMul = {-1.0,0.0,-1.0};
                                const float<3> indirect = clamp(dot(normal, normalize(sunDir * indirectMul)), 0.0, 1.0) * indirectCol;
                                const float shininess = 20.0f;
                                const float energyConservation = (8.0f + shininess) / (8.0f * PI);
                                const float<3> halfwayDir = normalize(sunDir + viewDir);
                                const float specular = energyConservation * pow(max(dot(normal, halfwayDir), 0.0f), shininess);
                                color *= indirect + sky + sun + specular;
                                color *= 0.8f;
                                #endif
                                
                                framebufferColor[index * FRAMEBUFFER_COLOR_BYTES + 0] = float_to_srgb8(color[0]);
                                framebufferColor[index * FRAMEBUFFER_COLOR_BYTES + 1] = float_to_srgb8(color[1]);
                                framebufferColor[index * FRAMEBUFFER_COLOR_BYTES + 2] = float_to_srgb8(color[2]);
                            }
                            // else framebufferColor[(x + y * frameSizeX) * 4 + 1] = 255;
                        }
                        // else framebufferColor[(x + y * frameSizeX) * 4] = 255;
                    }
    
                    // One step to the right
                    w0 += edge0.oneStepX;
                    w1 += edge1.oneStepX;
                    w2 += edge2.oneStepX;
                }
                
                // Step one row
                edge0.valueX += edge0.oneStepY;
                edge1.valueX += edge1.oneStepY;
                edge2.valueX += edge2.oneStepY;
            }
                    
            triangleEnd:;
        }
    }
}
