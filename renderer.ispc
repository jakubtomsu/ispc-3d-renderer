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

static inline void addColorToPixel(uniform uint8 framebufferColor[], uniform const int frameSizeX, uniform const int x, uniform const int y, uniform const uint8<3> color) {
    uniform const int pixelIndex = (x + y * frameSizeX) * FRAMEBUFFER_COLOR_BYTES;
    framebufferColor[pixelIndex + 0] = (uint8)clamp((uniform int)framebufferColor[pixelIndex + 0] + color.r, 0, 255);
    framebufferColor[pixelIndex + 1] = (uint8)clamp((uniform int)framebufferColor[pixelIndex + 1] + color.g, 0, 255);
    framebufferColor[pixelIndex + 2] = (uint8)clamp((uniform int)framebufferColor[pixelIndex + 2] + color.b, 0, 255);
}

void drawDebugLine(uniform uint8 framebufferColor[],
              uniform const int frameSizeX, uniform const int frameSizeY,
              uniform const int ax, uniform const int ay, uniform const int bx, uniform const int by,
              uniform const uint8<3> color) {
    uniform int xdiff = bx - ax;
	uniform int ydiff = by - ay;

	if(xdiff == 0 && ydiff == 0) {
		return;
	}
    
	if(abs(xdiff) > abs(ydiff)) {
		uniform int xmin, xmax;
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
		uniform const float slope = (float)ydiff / (float)xdiff;
		for(uniform int x = xmin; x <= xmax; x++) {
			uniform int y = ay + (int)((float)(x - ax) * slope);
            if(y >= 0 && y < frameSizeY) {
			    addColorToPixel(framebufferColor, frameSizeX, x, y, color);
            }
		}
	} else {
		uniform int ymin, ymax;
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
		uniform const float slope = (float)xdiff / (float)ydiff;
		for(uniform int y = ymin; y <= ymax; y++) {
			uniform int x = ax + (int)((float)(y - ay) * slope);
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

struct RenderFrameParams {
    uint8* framebufferColor;
    uint16* framebufferDepth;
    int frameSizeX;
    int frameSizeY;
    float* pointData;
    int pointNum;
    float transformMat4[4][4];
    float<3> camera;
    bool enableWireframe;
};

// Main function for rendering the frame.
export void renderFrame(RenderFrameParams* uniform params) {
    memset(params->framebufferColor, 42, params->frameSizeX * params->frameSizeY * FRAMEBUFFER_COLOR_BYTES);
    memset(params->framebufferDepth, 0xff, params->frameSizeX * params->frameSizeY * FRAMEBUFFER_DEPTH_BYTES);

    if(params->enableWireframe) {
        // Render Geometry
        for(uniform int pointpixelIndex = 0; pointpixelIndex < params->pointNum; pointpixelIndex += VERTEX_FLOATS * 3) {
            // Load vertex data
            uniform float<4> positions[3] = {
                {params->pointData[pointpixelIndex + 0], params->pointData[pointpixelIndex + 1], params->pointData[pointpixelIndex + 2], 1.0f},
                {params->pointData[pointpixelIndex + 6], params->pointData[pointpixelIndex + 7], params->pointData[pointpixelIndex + 8], 1.0f},
                {params->pointData[pointpixelIndex + 12], params->pointData[pointpixelIndex + 13], params->pointData[pointpixelIndex + 14], 1.0f},
            };
    
            uniform float<4> transformedPositions[3] = {0};
            varying bool shouldSkipTriangle = false;

            foreach(v = 0 ... 3, row = 0 ... 4) {
                float sum = 0.0f;
                for(uniform int col = 0; col < 4; col++) {
                    sum += params->transformMat4[col][row] * positions[v][col];
                }
                transformedPositions[v][row] = sum;
                shouldSkipTriangle |= transformedPositions[v].z < 0.0f;
            }
            
            if(any(shouldSkipTriangle)) goto wireframeEnd;
            
            foreach(v = 0 ... 3, e = 0 ... 3) {
                transformedPositions[v][e] /= transformedPositions[v].w;
            }
            
            // Transform into pixel positions
            uniform const int<2> v0 = transformToPixelCoord(transformedPositions[0].xy, params->frameSizeX, params->frameSizeY);
            uniform const int<2> v1 = transformToPixelCoord(transformedPositions[1].xy, params->frameSizeX, params->frameSizeY);
            uniform const int<2> v2 = transformToPixelCoord(transformedPositions[2].xy, params->frameSizeX, params->frameSizeY);
        
            uniform const uint8<3> triLineCol = {2, 20, 5};
            drawDebugLine(params->framebufferColor, params->frameSizeX, params->frameSizeY, v0.x, v0.y, v1.x, v1.y, triLineCol);
            drawDebugLine(params->framebufferColor, params->frameSizeX, params->frameSizeY, v1.x, v1.y, v2.x, v2.y, triLineCol);
            drawDebugLine(params->framebufferColor, params->frameSizeX, params->frameSizeY, v2.x, v2.y, v0.x, v0.y, triLineCol);
            
            wireframeEnd:;
        }

    } else {
            
        uniform const float<3> sunDir = {0.707, 0.707, 0};
        uniform const float<3> sunCol = {1.64,1.27,0.99};
        uniform const float<3> skyCol = {0.16,0.20,0.28};
        uniform const float<3> indirectCol = {0.40,0.28,0.20};
        uniform const float<3> diffuseCol = {0.85f, 0.1f, 0.3f};
        // uniform const float<3> diffuseCol = {0, 1.0f, 0.8f};

        // Render Geometry
        for(uniform int pointpixelIndex = 0; pointpixelIndex < params->pointNum; pointpixelIndex += VERTEX_FLOATS * 3) {
            // Load vertex positions
            uniform float<4> positions[3] = {
                {params->pointData[pointpixelIndex + 0], params->pointData[pointpixelIndex + 1], params->pointData[pointpixelIndex + 2], 1.0f},
                {params->pointData[pointpixelIndex + 6], params->pointData[pointpixelIndex + 7], params->pointData[pointpixelIndex + 8], 1.0f},
                {params->pointData[pointpixelIndex + 12], params->pointData[pointpixelIndex + 13], params->pointData[pointpixelIndex + 14], 1.0f},
            };
            
            uniform const float area = edgeFunc(positions[0].xyz, positions[1].xyz, positions[2].xyz);

            // Backface culling
            if(area > 0.0) {
                goto triangleEnd;
            }
    
            uniform float<4> transformedPositions[3] = {0};
            uniform float<3> screenPositonClipZ;

            // HACK: don't draw any triangles with a vertex behind the near plane
            varying bool shouldSkipTriangle = false;

            foreach(v = 0 ... 3, row = 0 ... 4) {
                float sum = 0.0f;
                for(uniform int col = 0; col < 4; col++) {
                    sum += params->transformMat4[col][row] * positions[v][col];
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
            uniform const int<2> v0 = transformToPixelCoord(transformedPositions[0].xy, params->frameSizeX, params->frameSizeY);
            uniform const int<2> v1 = transformToPixelCoord(transformedPositions[1].xy, params->frameSizeX, params->frameSizeY);
            uniform const int<2> v2 = transformToPixelCoord(transformedPositions[2].xy, params->frameSizeX, params->frameSizeY);
    
            // Compute triangle bounding box
            uniform const int<2> bbMin = {
                max(0, minInt3(v0.x, v1.x, v2.x)),
                max(0, minInt3(v0.y, v1.y, v2.y)),
            };
            uniform const int<2> bbMax = {
                min(params->frameSizeX - 1, maxInt3(v0.x, v1.x, v2.x)),
                min(params->frameSizeY - 1, maxInt3(v0.y, v1.y, v2.y)),
            };
                
            uniform const float screenPosInvZ0 = 1.0f / screenPositonClipZ[0];
            uniform const float screenPosInvZ1 = 1.0f / screenPositonClipZ[1];
            uniform const float screenPosInvZ2 = 1.0f / screenPositonClipZ[2];
            
            // Load vertex normals
            uniform float<3> normals[3] = {
                {params->pointData[pointpixelIndex + 3], params->pointData[pointpixelIndex + 4], params->pointData[pointpixelIndex + 5]},
                {params->pointData[pointpixelIndex + 9], params->pointData[pointpixelIndex + 10], params->pointData[pointpixelIndex + 11]},
                {params->pointData[pointpixelIndex + 15], params->pointData[pointpixelIndex + 16], params->pointData[pointpixelIndex + 17]},
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
                            const int pixelIndex = x + y * params->frameSizeX;
                            const uint prevDepth = params->framebufferDepth[pixelIndex];
                            // Note: the sqrt is a hack. I'm not really sure how to encode the depth
                            // properly, but linear is definitely not the right way.
                            const uint depth16 = (int)(sqrt(depth) * 2000.0f);
                            if(depth16 < prevDepth) {
                                params->framebufferDepth[pixelIndex] = depth16;
    
                                const float<3> normal = (w0a * normals[0] + w1a * normals[1] + w2a * normals[2]) * z;
                                const float<3> position = (w0a * positions[0].xyz + w1a * positions[1].xyz + w2a * positions[2].xyz) * z;
    
                                const float<3> viewDir = normalize(params->camera - position);
                                
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
                                
                                params->framebufferColor[pixelIndex * FRAMEBUFFER_COLOR_BYTES + 0] = float_to_srgb8(color[0]);
                                params->framebufferColor[pixelIndex * FRAMEBUFFER_COLOR_BYTES + 1] = float_to_srgb8(color[1]);
                                params->framebufferColor[pixelIndex * FRAMEBUFFER_COLOR_BYTES + 2] = float_to_srgb8(color[2]);
                            }
                            // else params->framebufferColor[(x + y * params->frameSizeX) * 4 + 1] = 255;
                        }
                        else params->framebufferColor[(x + y * params->frameSizeX) * 4] = 255;
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
