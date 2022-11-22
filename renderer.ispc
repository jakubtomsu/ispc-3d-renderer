inline int minInt3(const int x, const int y, const int z) {
    return min(x, min(y, z));
}

inline int maxInt3(const int x, const int y, const int z) {
    return max(x, max(y, z));
}

typedef int<2> Point2D;

int orient2d(const Point2D& a, const Point2D& b, const Point2D& c) {
    return (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x);
}

export void renderTriangles(const uniform int v0x, const uniform int v0y,
                            const uniform int v1x, const uniform int v1y,
                            const uniform int v2x, const uniform int v2y,
                            const uniform int screenX, const uniform int screenY) {
    // Compute triangle bounding box
    const int<2> bbMin = {max(0, minInt3(v0x, v1x, v2x)),
                          max(0, minInt3(v0y, v1y, v2y))};
    const int<2> bbMax = {min(screenX - 1, maxInt3(v0x, v1x, v2x)),
                          min(screenY - 1, maxInt3(v0y, v1y, v2y))};
                    
    const int a01 = v0y - v1y;
    const int a12 = v1y - v2y;
    const int a20 = v2y - v0y;
    const int b01 = v1x - v0x;
    const int b12 = v2x - v1x;
    const int b20 = v0x - v2x;

    // Triangle setup
}