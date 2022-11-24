// https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/
// https://fgiesen.wordpress.com/2013/02/10/optimizing-the-basic-rasterizer/
// https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/perspective-correct-interpolation-vertex-attributes

inline int minInt3(const int x, const int y, const int z) {
    return min(x, min(y, z));
}

inline int maxInt3(const int x, const int y, const int z) {
    return max(x, max(y, z));
}

int orient2d(const int<2>& a, const int<2>& b, const int<2>& c) {
    return (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x);
}

inline float edgeFunc(const float<3>& a, const float<3>& b, const float<3>& c) {
    return (c[0] - a[0]) * (b[1] - a[1]) - (c[1] - a[1]) * (b[0] - a[0]);
}

#define MAX_CLIPPED_TRIANGLES 2
#define BYTES_PER_PIXEL 4

inline void setPixel(uniform uint8 outFrame[], const int frameSizeX, const int x, const int y, const uint8<3> color) {
    const int index = (x + y * frameSizeX) * BYTES_PER_PIXEL;
    outFrame[index + 0] = color.r;
    outFrame[index + 1] = color.g;
    outFrame[index + 2] = color.b;
}

void drawLine(uniform uint8 outFrame[],
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
			    setPixel(outFrame, frameSizeX, x, y, color);
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
			    setPixel(outFrame, frameSizeX, x, y, color);
            }
		}
	}
}

export void renderFrame(uniform uint8 outFrame[],
                        const uniform int frameSizeX, const uniform int frameSizeY,
                        const uniform float pointData[], const uniform int pointNum,
                        const uniform float transformMat4[4][4]) {
    memset(outFrame, 66, frameSizeX * frameSizeY * BYTES_PER_PIXEL);
    
    const uint8<3> lineCol = {77, 77, 77};
    drawLine(outFrame, frameSizeX, frameSizeY, 0, 0, frameSizeX, frameSizeY, lineCol);
    drawLine(outFrame, frameSizeX, frameSizeY, frameSizeX, 0, 0, frameSizeY, lineCol);
                            
    // Render Geometry
    for(int pointIndex = 0; pointIndex < pointNum; pointIndex += 3 * 3) {
        // Load vertex data
        float<4> positions[3] = {
            {pointData[pointIndex + 0], pointData[pointIndex + 1], pointData[pointIndex + 2], 1.0f},
            {pointData[pointIndex + 3], pointData[pointIndex + 4], pointData[pointIndex + 5], 1.0f},
            {pointData[pointIndex + 6], pointData[pointIndex + 7], pointData[pointIndex + 8], 1.0f},
        };

        float<4> transformedPositions[3];
        float<3> screenPositonClipZ;
        for(int v = 0; v < 3; v++) {
        // foreach(v = 0...3) {
            for(int row = 0; row < 4; row++) {
                float sum = 0.0f;
                for(int col = 0; col < 4; col++) {
                    sum += transformMat4[col][row] * positions[v][col];
                }
                transformedPositions[v][row] = sum;
            }
            transformedPositions[v].x /= transformedPositions[v].w;
            transformedPositions[v].y /= transformedPositions[v].w;
            transformedPositions[v].z /= transformedPositions[v].w;
            screenPositonClipZ[v] = transformedPositions[v].z;
        }
        
        // Clip triangles
        // Note: this clips only agains the near plane.
        float<4> clipped[MAX_CLIPPED_TRIANGLES * 3];
        int clippedNum = 0;
        {
            const float<3> d = screenPositonClipZ;
            const float plane = 0.0f;
            const int numPositive = (d[0] > plane ? 1 : 0) + (d[1] > plane ? 1 : 0) + (d[1] > plane ? 1 : 0);
            if(numPositive == 3) {
                // use the full triangle
                clipped[0] = transformedPositions[0];
                clipped[1] = transformedPositions[1];
                clipped[2] = transformedPositions[2];
                clippedNum = 3;
            } else if(numPositive == 0) {
                continue;
            } else if(numPositive == 1) {
                continue;
            } else { //< Only one negative
                continue;
            }
        }
        
        // Transform into pixel positions
        const int<2> v0 = {
            (transformedPositions[0].x * 0.5f + 0.5f) * frameSizeX,
            (transformedPositions[0].y * 0.5f + 0.5f) * frameSizeY,
        };
        const int<2> v1 = {
            (transformedPositions[1].x * 0.5f + 0.5f) * frameSizeX,
            (transformedPositions[1].y * 0.5f + 0.5f) * frameSizeY,
        };
        const int<2> v2 = {
            (transformedPositions[2].x * 0.5f + 0.5f) * frameSizeX,
            (transformedPositions[2].y * 0.5f + 0.5f) * frameSizeY,
        };

        // Compute triangle bounding box
        const int<2> bbMin = {max(0, minInt3(v0.x, v1.x, v2.x)),
                              max(0, minInt3(v0.y, v1.y, v2.y))};
        const int<2> bbMax = {min(frameSizeX - 1, maxInt3(v0.x, v1.x, v2.x)),
                              min(frameSizeY - 1, maxInt3(v0.y, v1.y, v2.y))};
    
        // Triangle setup
        const int a01 = v0.y - v1.y;
        const int a12 = v1.y - v2.y;
        const int a20 = v2.y - v0.y;
        const int b01 = v1.x - v0.x;
        const int b12 = v2.x - v1.x;
        const int b20 = v0.x - v2.x;
        
        // Barycentric coordinates at bbMin corner
        int<2> p = bbMin;
        int w0Row = orient2d(v1, v2, p);
        int w1Row = orient2d(v2, v0, p);
        int w2Row = orient2d(v0, v1, p);
        
        const float area = edgeFunc(positions[0].xyz, positions[1].xyz, positions[2].xyz);
        
        const uint8<3> triangleColor = 100 + (pointIndex * 10) % 50;
        
        const float screenPosInvZ0 = 1.0f / screenPositonClipZ[0];
        const float screenPosInvZ1 = 1.0f / screenPositonClipZ[1];
        const float screenPosInvZ2 = 1.0f / screenPositonClipZ[2];

        const float<3> col0 = {255 * screenPosInvZ0, 0, 0};
        const float<3> col1 = {0, 255 * screenPosInvZ1, 0};
        const float<3> col2 = {0, 0, 255 * screenPosInvZ2};
        
        for(p.y = bbMin.y; p.y <= bbMax.y; p.y++) {
            // Barycentric coords at start of the row
            int w0 = w0Row;
            int w1 = w1Row;
            int w2 = w2Row;
            
            for(p.x = bbMin.x; p.x <= bbMax.x; p.x++) {
                // If 'p' is on or inside all edges, render the pixel
                //if(w0 >= 0 && w1 >= 0 && w2 >= 0) {
                if((w0 | w1 | w2) >= 0) {
                    const float w0a = (float)w0 / area;
                    const float w1a = (float)w1 / area;
                    const float w2a = (float)w2 / area;
                    const float z = 1.0f / (w0a * screenPosInvZ0 + w1a * screenPosInvZ1 + w2a * screenPosInvZ2);
                    const float r = (w0a * col0[0] + w1a * col1[0] + w2a * col2[0]) * z;
                    const float g = (w0a * col0[1] + w1a * col1[1] + w2a * col2[1]) * z;
                    const float b = (w0a * col0[2] + w1a * col1[2] + w2a * col2[2]) * z;
                    // const float oneOverZ = w0a * screenPositonClipZ[0] + w1a * screenPositonClipZ[1] + w2a * screenPositonClipZ[2];
                    // if(z > 0.0f) {
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 0] = r;
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 1] = g;
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 2] = b;
                    // } else outFrame[(p.x + p.y * frameSizeX) * 4 + 0] = 255;
                }
                
                // One step to the right
                w0 += a12;
                w1 += a20;
                w2 += a01;
            }
            
            // Step one row
            w0Row += b12;
            w1Row += b20;
            w2Row += b01;
        }
        
        const uint8<3> triLineCol = {255, 255, 255};
        drawLine(outFrame, frameSizeX, frameSizeY, v0.x, v0.y, v1.x, v1.y, triLineCol);
        drawLine(outFrame, frameSizeX, frameSizeY, v1.x, v1.y, v2.x, v2.y, triLineCol);
        drawLine(outFrame, frameSizeX, frameSizeY, v2.x, v2.y, v0.x, v0.y, triLineCol);
    }
}
