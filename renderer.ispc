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

export void renderFrame(uniform uint8 outFrame[],
                        const uniform int frameSizeX, const uniform int frameSizeY,
                        const uniform float pointData[], const uniform int pointNum,
                        const uniform float transformMat4[4][4]) {
    // Render Geometry
    for(int pointIndex = 0; pointIndex < pointNum; pointIndex += 3 * 3) {
        // Load vertex data
        float<4> positions[3] = {
            {pointData[pointIndex + 0], pointData[pointIndex + 1], pointData[pointIndex + 2], 1.0f},
            {pointData[pointIndex + 3], pointData[pointIndex + 4], pointData[pointIndex + 5], 1.0f},
            {pointData[pointIndex + 6], pointData[pointIndex + 7], pointData[pointIndex + 8], 1.0f},
        };

        float<4> screenPositions[3] = {0};
        for(int v = 0; v < 3; v++) {
            for(int row = 0; row < 4; row++) {
                float sum = 0.0f;
                for(int col = 0; col < 4; col++) {
                    sum += transformMat4[col][row] * positions[v][col];
                }
                screenPositions[v][row] = sum;
            }
            screenPositions[v].x /= screenPositions[v].w;
            screenPositions[v].y /= screenPositions[v].w;
            screenPositions[v].z /= screenPositions[v].w;
        }
        
        // Transform into pixel positions
        const int<2> v0 = {
            (screenPositions[0].x * 0.5f + 0.5f) * frameSizeX,
            (screenPositions[0].y * 0.5f + 0.5f) * frameSizeY,
        };
        const int<2> v1 = {
            (screenPositions[1].x * 0.5f + 0.5f) * frameSizeX,
            (screenPositions[1].y * 0.5f + 0.5f) * frameSizeY,
        };
        const int<2> v2 = {
            (screenPositions[2].x * 0.5f + 0.5f) * frameSizeX,
            (screenPositions[2].y * 0.5f + 0.5f) * frameSizeY,
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
        
        const float screenPosInvZ0 = 1.0f / screenPositions[0].z;
        const float screenPosInvZ1 = 1.0f / screenPositions[1].z;
        const float screenPosInvZ2 = 1.0f / screenPositions[2].z;
        
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
                    const float oneOverZ = w0a * screenPositions[0].z + w1a * screenPositions[1].z + w2a * screenPositions[2].z;
                    const float z = 1.0f / (w0a * screenPosInvZ0 + w1a * screenPosInvZ1 + w2a * screenPosInvZ2);
                    if(z > 0.0f) {
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 0] = z * 100.0f;
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 1] = z * 100.0f;
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 2] = z * 100.0f;
                    } else {
                    outFrame[(p.x + p.y * frameSizeX) * 4 + 0] = 255;
                    }
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
    }
}