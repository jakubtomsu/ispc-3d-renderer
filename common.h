#pragma once

#define FRAMEBUFFER_COLOR_BYTES 4
#define FRAMEBUFFER_DEPTH_BYTES 2
#define VERTEX_FLOATS 6

#if defined(ISPC)
typedef uint16 DepthType;
#else
#include <stdint.h>
typedef uint16_t DepthType;
#endif