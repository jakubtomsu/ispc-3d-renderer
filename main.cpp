#include <assert.h>
#include <glad/glad.h>
#include <glfw/glfw3.h>
#include <math.h> // sqrt
#include <stdint.h>
#include <stdio.h>  // printf
#include <stdlib.h> // malloc
#include <string.h> // memset
#include "renderer_ispc.h"
#include "common.h"
#define FAST_OBJ_IMPLEMENTATION
#include "fast_obj.h"


#define staticArrayLen(arr) (sizeof(arr) / sizeof(arr[0]))
#define PI                  3.14159265359f

union Vec2 {
    float elems[2];
    struct {
        float x, y;
    };
};

union Vec3 {
    float elems[3];
    struct {
        float x, y, z;
    };
};

union Vec4 {
    float elems[4];
    struct {
        float x, y, z, w;
    };
};

typedef Vec4 Quat;
#define QUAT_IDENTITY \
    Quat { 0.0f, 0.0f, 0.0f, 1.0f }

// 4x4 column-major matrix
union Mat4 {
    float elems[4][4];
    float elemsFlat[4 * 4];
};

struct Camera {
    Vec3 pos = {};
    Quat rot = QUAT_IDENTITY;
    float nearPlane = 0.005f;
    float farPlane = 1000.0f;
    float fieldOfView = 90.0f;
};

struct Context {
    int frameSizeX;
    int frameSizeY;
    uint8_t* framebufferColor;
    uint16_t* framebufferDepth;
    Camera camera;
    Vec3 cameraEuler;
    Vec2 cursor;
    bool enableWriteframe;
};

static Context g_context = {};

static size_t getFrameImageSizeInBytes() {
    return FRAMEBUFFER_COLOR_BYTES * g_context.frameSizeX * g_context.frameSizeY;
}

static void changeFrameSize(const int x, const int y) {
    if(x <= 0 || y <= 0) {
        return;
    }
    if(x == g_context.frameSizeX && y == g_context.frameSizeY) {
        return;
    }
    g_context.frameSizeX = x;
    g_context.frameSizeY = y;
    if(g_context.framebufferColor != nullptr) free(g_context.framebufferColor);
    if(g_context.framebufferDepth != nullptr) free(g_context.framebufferDepth);
    g_context.framebufferColor = (uint8_t*)malloc(getFrameImageSizeInBytes());
    g_context.framebufferDepth =
        (uint16_t*)malloc(FRAMEBUFFER_DEPTH_BYTES * g_context.frameSizeX * g_context.frameSizeY);
    assert(g_context.framebufferColor != nullptr);
    assert(g_context.framebufferDepth != nullptr);
}

// glfw: whenever the window size changed (by OS or user resize) this callback
// function executes
static void framebufferSizeChangedGlfwCallback(GLFWwindow* window, int width, int height) {
    // make sure the viewport matches the new window dimensions; note that width
    // and height will be significantly larger than specified on retina
    // displays.
    glViewport(0, 0, width, height);
}

static void GLAPIENTRY debugMessageOpenglCallback(
    GLenum source,
    GLenum type,
    GLuint id,
    GLenum severity,
    GLsizei length,
    const GLchar* message,
    const void* userParam) {
    printf(
        "[OpenGl Error]: %s type = 0x%x, severity = 0x%x, message = %s\n",
        (type == GL_DEBUG_TYPE_ERROR ? "** GL ERROR **" : ""),
        type,
        severity,
        message);
}

static void uploadFrameImageToGpu(GLuint texture) {
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA,
        g_context.frameSizeX,
        g_context.frameSizeY,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        g_context.framebufferColor);
}

static inline uint8_t floatToUNorm8(const float value) { return (uint8_t)(value * 255.0f); }

static void renderFrameCpp() {
    const float time = glfwGetTime();
    assert(g_context.framebufferColor != nullptr);
    const int frameSizeX = g_context.frameSizeX;
    const int frameSizeY = g_context.frameSizeY;
    for(int x = 0; x < frameSizeX; x++) {
        for(int y = 0; y < frameSizeY; y++) {
            g_context.framebufferColor[(x + y * frameSizeX) * FRAMEBUFFER_COLOR_BYTES] =
                floatToUNorm8((float)x / (float)frameSizeX + time);
        }
    }
}

static Vec3 vec3Cross(const Vec3 left, const Vec3 right) {
    return {
        (left.y * right.z) - (left.z * right.y),
        (left.z * right.x) - (left.x * right.z),
        (left.x * right.y) - (left.y * right.x)};
}

static Vec3 vec3MulF(const Vec3 v, const float f) { return {v.x * f, v.y * f, v.z * f}; }

static Vec3 vec3Add(const Vec3 left, const Vec3 right) {
    return {left.x + right.x, left.y + right.y, left.z + right.z};
}

static float quatDot(const Quat left, const Quat right) {
    return left.x * right.x + left.y * right.y + left.z * right.z + left.w * right.w;
}

static Vec3 quatMulVec3(const Quat q, const Vec3 v) {
    const Vec3 t = vec3MulF(vec3Cross({q.x, q.y, q.z}, v), 2.0f);
    return vec3Add(vec3Add(v, vec3MulF(t, q.w)), vec3Cross({q.x, q.y, q.z}, t));
}

static Quat quatDivF(const Quat q, const float f) { return {q.x / f, q.y / f, q.z / f, q.w / f}; }

static Quat quatNormalize(const Quat q) {
    const float len = sqrtf(quatDot(q, q));
    return quatDivF(q, len);
}

static Quat quatInv(const Quat left) {
    Quat conj = {-left.x, -left.y, -left.z, left.w};
    const float normSq = quatDot(left, left);
    return quatDivF(conj, normSq);
}

static Quat quatFromAxisAngle(const Vec3 axis, const float angle) {
    const float rotSin = sinf(angle * 0.5f);
    Quat result;
    for(int i = 0; i < 3; i++) result.elems[i] = axis.elems[i] * rotSin;
    result.w = cosf(angle * 0.5f);
    return result;
}

static Quat quatMul(const Quat left, const Quat right) {
    Quat result;
    result.x = (left.x * right.w) + (left.y * right.z) - (left.z * right.y) + (left.w * right.x);
    result.y = (-left.x * right.z) + (left.y * right.w) + (left.z * right.x) + (left.w * right.y);
    result.z = (left.x * right.y) - (left.y * right.x) + (left.z * right.w) + (left.w * right.z);
    result.w = (-left.x * right.x) - (left.y * right.y) - (left.z * right.z) + (left.w * right.w);
    return result;
}

static Quat quatFromEuler(const Vec3 euler) {
    Quat result = QUAT_IDENTITY;
    result = quatMul(result, quatFromAxisAngle({0, 0, 1}, euler.z));
    result = quatMul(result, quatFromAxisAngle({0, 1, 0}, euler.y));
    result = quatMul(result, quatFromAxisAngle({1, 0, 0}, euler.x));
    return quatNormalize(result);
}

static Mat4 quatToMat4(const Quat q) {
    float XX = q.x * q.x;
    float YY = q.y * q.y;
    float ZZ = q.z * q.z;
    float XY = q.x * q.y;
    float XZ = q.x * q.z;
    float YZ = q.y * q.z;
    float WX = q.w * q.x;
    float WY = q.w * q.y;
    float WZ = q.w * q.z;

    Mat4 result;
    result.elems[0][0] = 1.0f - 2.0f * (YY + ZZ);
    result.elems[0][1] = 2.0f * (XY + WZ);
    result.elems[0][2] = 2.0f * (XZ - WY);
    result.elems[0][3] = 0.0f;

    result.elems[1][0] = 2.0f * (XY - WZ);
    result.elems[1][1] = 1.0f - 2.0f * (XX + ZZ);
    result.elems[1][2] = 2.0f * (YZ + WX);
    result.elems[1][3] = 0.0f;

    result.elems[2][0] = 2.0f * (XZ + WY);
    result.elems[2][1] = 2.0f * (YZ - WX);
    result.elems[2][2] = 1.0f - 2.0f * (XX + YY);
    result.elems[2][3] = 0.0f;

    result.elems[3][0] = 0.0f;
    result.elems[3][1] = 0.0f;
    result.elems[3][2] = 0.0f;
    result.elems[3][3] = 1.0f;

    return result;
}

Mat4 mat4Mul(const Mat4 left, const Mat4 right) {
    Mat4 result;
    for(int columns = 0; columns < 4; ++columns) {
        for(int rows = 0; rows < 4; ++rows) {
            float sum = 0;
            for(int currentMatrix = 0; currentMatrix < 4; ++currentMatrix) {
                sum += left.elems[currentMatrix][rows] * right.elems[columns][currentMatrix];
            }
            result.elems[columns][rows] = sum;
        }
    }

    return result;
}

static Mat4 mat4Perspective(const float fov, const float aspectRatioXOverY, const float near, const float far) {
    Mat4 result = {};
    const float cotangent = 1.0f / tanf(fov * (PI / 360.0f));
    const float a = cotangent / aspectRatioXOverY;
    const float b = cotangent;
    const float c = (near + far) / (near - far);
    const float d = (2.0f * near * far) / (near - far);
    const float e = -1.0f;
    result.elems[0][0] = a;
    result.elems[1][1] = b;
    result.elems[2][2] = c;
    result.elems[3][2] = d;
    result.elems[2][3] = e;
    return result;
}

// View to screen matrix
static Mat4 calcCameraMatrix(const Camera& camera) {
    Mat4 view = {};
    // Load identity matrix
    view.elems[0][0] = 1.0f;
    view.elems[1][1] = 1.0f;
    view.elems[2][2] = 1.0f;
    view.elems[3][3] = 1.0f;
    // Apply inverse translation
    view.elems[3][0] = -camera.pos.x;
    view.elems[3][1] = -camera.pos.y;
    view.elems[3][2] = -camera.pos.z;
    // Apply inverse rotation
    view = mat4Mul(quatToMat4(quatInv(camera.rot)), view);

    const Mat4 perspective = mat4Perspective(
        camera.fieldOfView,
        (float)g_context.frameSizeX / (float)g_context.frameSizeY,
        camera.nearPlane,
        camera.farPlane);

    // return view;
    return mat4Mul(perspective, view);
}

static inline float clamp(const float value, const float minValue, const float maxValue) {
    if(value < minValue) {
        return minValue;
    }
    if(value > maxValue) {
        return maxValue;
    }
    return value;
}

// process all input: query GLFW whether relevant keys are pressed/released this
// frame and react accordingly
static void processInput(GLFWwindow* window, const float deltaTime) {
    if(glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS) glfwSetWindowShouldClose(window, true);

    double xpos, ypos;
    glfwGetCursorPos(window, &xpos, &ypos);
    const Vec2 mouseDelta = {
        (float)(xpos - (double)g_context.cursor.x),
        (float)(ypos - (double)g_context.cursor.y),
    };
    g_context.cursor = {(float)xpos, (float)ypos};

    // Move
    Vec3 localMove = {};
    const float speed = 0.4f * deltaTime * (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) ? 4.0f : 1.0f) *
                        (glfwGetKey(window, GLFW_KEY_LEFT_CONTROL) ? 0.25f : 1.0f);
    if(glfwGetKey(window, GLFW_KEY_W)) localMove.z -= speed;
    if(glfwGetKey(window, GLFW_KEY_S)) localMove.z += speed;
    if(glfwGetKey(window, GLFW_KEY_A)) localMove.x -= speed;
    if(glfwGetKey(window, GLFW_KEY_D)) localMove.x += speed;
    if(glfwGetKey(window, GLFW_KEY_E)) g_context.camera.pos.y += speed;
    if(glfwGetKey(window, GLFW_KEY_Q)) g_context.camera.pos.y -= speed;

    g_context.cameraEuler.x -= mouseDelta.y * 0.005f;
    g_context.cameraEuler.y -= mouseDelta.x * 0.005f;
    // g_context.cameraEuler.x = clamp(g_context.cameraEuler.x, -PI * 0.5f, PI * 0.5f);

    g_context.camera.rot = quatFromEuler(g_context.cameraEuler);
    g_context.camera.pos = vec3Add(g_context.camera.pos, quatMulVec3(g_context.camera.rot, localMove));

    // Wireframe
    g_context.enableWriteframe = false;
    if(glfwGetKey(window, GLFW_KEY_V)) g_context.enableWriteframe = true;

    // Zoom
    if(glfwGetKey(window, GLFW_KEY_C)) g_context.camera.fieldOfView -= 60.0f * deltaTime;
    if(glfwGetKey(window, GLFW_KEY_Z)) g_context.camera.fieldOfView += 60.0f * deltaTime;
    g_context.camera.fieldOfView = clamp(g_context.camera.fieldOfView, 10.0f, 170.0f);

    // Reset
    if(glfwGetKey(window, GLFW_KEY_R)) {
        g_context.camera.pos = {0, 0, 0};
        g_context.camera.rot = QUAT_IDENTITY;
    }
}

// returns new vertexBufferLen
size_t loadModel(
    const char* path,
    float* vertexBuffer,
    const size_t vertexBufferLen,
    const size_t vertexBufferSize,
    const Vec3 offset = {},
    const float scale = 1.0f) {
    fastObjMesh* mesh = fast_obj_read(path);
    assert(mesh);
    size_t len = vertexBufferLen;
    for(unsigned int ii = 0; ii < mesh->group_count; ii++) {
        const fastObjGroup& grp = mesh->groups[ii];
        int idx = 0;
        for(unsigned int jj = 0; jj < grp.face_count; jj++) {
            unsigned int fv = mesh->face_vertices[grp.face_offset + jj];
            for(unsigned int kk = 0; kk < fv; kk++) {
                fastObjIndex mi = mesh->indices[grp.index_offset + idx];
                if(mi.p) {
                    vertexBuffer[len + 0] = offset.elems[0] + mesh->positions[3 * mi.p + 0] * scale;
                    vertexBuffer[len + 1] = offset.elems[1] + mesh->positions[3 * mi.p + 1] * scale;
                    vertexBuffer[len + 2] = offset.elems[2] + mesh->positions[3 * mi.p + 2] * scale;
                    vertexBuffer[len + 3] = mesh->normals[3 * mi.n + 0];
                    vertexBuffer[len + 4] = mesh->normals[3 * mi.n + 1];
                    vertexBuffer[len + 5] = mesh->normals[3 * mi.n + 2];
                    len += VERTEX_FLOATS;
                    assert(len < vertexBufferSize);
                }
                idx++;
            }
        }
    }
    fast_obj_destroy(mesh);
    return len;
}

// MAIN
int main() {
    printf("Hello!\n");
    // glfw: initialize and configure
    glfwInit();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

#ifdef __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    const int startWindowX = 800;
    const int startWindowY = 600;
    // glfw window creation
    GLFWwindow* window = glfwCreateWindow(startWindowX, startWindowY, "ISPC software rasterizer", nullptr, nullptr);
    if(window == nullptr) {
        printf("[glfwCreateWindow] Failed to open a window.");
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebufferSizeChangedGlfwCallback);
    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    glfwSwapInterval(0); //< V-Sync

    changeFrameSize(startWindowX, startWindowY);

    // glad: load all OpenGL function pointers
    if(!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        printf("[gladLoadGLLoader] Failed to load OpenGl function pointers.");
        return -1;
    }

    glEnable(GL_DEBUG_OUTPUT);
    glDebugMessageCallback(debugMessageOpenglCallback, 0);

    // Compile Shaders
    GLint shaderProgram;
    {
        const char* vertSource =
            "#version 460 core\n"
            "layout(location = 0) in vec2 in_pos;\n"
            "layout(location = 0) out vec2 u_uv;\n"
            "void main() {\n"
            "   u_uv = (in_pos + vec2(1.0f, 1.0f)) * 0.5f;\n"
            "	gl_Position = vec4(in_pos.x, in_pos.y, 0.0f, 1.0f);\n"
            "}\n";

        const char* fragSource =
            "#version 460 core\n"
            "layout(location = 0) out vec4 out_fragColor;\n"
            "layout(location = 0) in vec2 u_uv;\n"
            "uniform sampler2D frameTexture;\n"
            "void main() {\n"
            "	out_fragColor = vec4(texture(frameTexture, u_uv).rgb, 1.0f);\n"
            "}\n";

        GLint success;
        char infoLog[512];

        GLint vertShader = glCreateShader(GL_VERTEX_SHADER);
        glShaderSource(vertShader, 1, &vertSource, nullptr);
        glCompileShader(vertShader);
        glGetShaderiv(vertShader, GL_COMPILE_STATUS, &success);
        if(!success) {
            glGetShaderInfoLog(vertShader, staticArrayLen(infoLog), nullptr, infoLog);
            printf("[glCompileShader] Vertex Shader Error: %s", infoLog);
            assert(false);
        }

        GLint fragShader = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fragShader, 1, &fragSource, nullptr);
        glCompileShader(fragShader);
        if(!success) {
            glGetShaderInfoLog(fragShader, staticArrayLen(infoLog), nullptr, infoLog);
            printf("[glCompileShader] Vertex Shader Error: %s", infoLog);
            assert(false);
        }

        shaderProgram = glCreateProgram();
        glAttachShader(shaderProgram, vertShader);
        glAttachShader(shaderProgram, fragShader);
        glLinkProgram(shaderProgram);
        glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success);
        if(!success) {
            glGetProgramInfoLog(shaderProgram, staticArrayLen(infoLog), nullptr, infoLog);
            printf("[glLinkProgram] Couldn't link the shader program: %s", infoLog);
            assert(false);
        }

        glDeleteShader(vertShader);
        glDeleteShader(fragShader);
    }

    // Quad Vertex Buffer Object
    GLuint quadVao;
    {
        float quadVerts[] = {
            -1.0f,
            -1.0f,
            1.0f,
            -1.0f,
            -1.0f,
            1.0f,
            -1.0f,
            1.0f,
            1.0f,
            -1.0f,
            1.0f,
            1.0f,
        };

        glGenVertexArrays(1, &quadVao);
        GLuint quadVbo;
        glGenBuffers(1, &quadVbo);
        glBindVertexArray(quadVao);
        glBindBuffer(GL_ARRAY_BUFFER, quadVbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof(quadVerts), quadVerts, GL_STATIC_DRAW);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
        glEnableVertexAttribArray(0);
    }

    GLuint frameTexture;
    {
        glGenTextures(1, &frameTexture);
        glBindTexture(GL_TEXTURE_2D, frameTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }

    static float vertexBuffer[1024 * 1024 * 20] = {};
    size_t vertexBufferLen = 0;
    vertexBufferLen =
        loadModel("models/swordfish.obj", &vertexBuffer[0], vertexBufferLen, staticArrayLen(vertexBuffer));
    // vertexBufferLen = loadModel(
    //     "models/teapot.obj", &vertexBuffer[0], vertexBufferLen, staticArrayLen(vertexBuffer), {2.5, 1, 0}, 0.1f);

    g_context.camera.pos = {-2, 1, 2};

    double prevTime = glfwGetTime();

    // render loop
    uint64_t frameIndex = 0;
    while(!glfwWindowShouldClose(window)) {
        glfwPollEvents();
        const double currentTime = glfwGetTime();
        const float deltaTime = clamp(currentTime - prevTime, 0.001f, 0.1f);
        prevTime = currentTime;
        frameIndex++;

        processInput(window, deltaTime);

        int currentWindowX = 0;
        int currentWindowY = 0;
        glfwGetWindowSize(window, &currentWindowX, &currentWindowY);

        if(g_context.frameSizeX != currentWindowX || g_context.frameSizeY != currentWindowY) {
            changeFrameSize(currentWindowX, currentWindowY);
        }

        g_context.camera.rot = quatNormalize(g_context.camera.rot);
        const Mat4 transformMat4 = calcCameraMatrix(g_context.camera);

        const double renderBegin = glfwGetTime();
        ispc::renderFrame(
            g_context.framebufferColor,
            g_context.framebufferDepth,
            g_context.frameSizeX,
            g_context.frameSizeY,
            &vertexBuffer[0],
            vertexBufferLen,
            &transformMat4.elems[0],
            g_context.camera.pos.x,
            g_context.camera.pos.y,
            g_context.camera.pos.z,
            g_context.enableWriteframe);
        const double renderTime = glfwGetTime() - renderBegin;

        uploadFrameImageToGpu(frameTexture);

        // Finish the rendering on the GPU - just draws a quad with the texture
        // on it
        glUseProgram(shaderProgram);
        glBindVertexArray(quadVao);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, frameTexture);
        glDrawArrays(GL_TRIANGLES, 0, 3 * 2);

        // Finish frame
        glfwSwapBuffers(window);

        // Dump info
        {
            char infoBuf[512] = {};
            snprintf(
                infoBuf,
                staticArrayLen(infoBuf),
                "dt:%fms fps:%i render:%fms x:%i y:%i vert:%ifloats",
                deltaTime * 1000.0f,
                (int)(1.0f / deltaTime),
                renderTime * 1000.0f,
                g_context.frameSizeX,
                g_context.frameSizeY,
                vertexBufferLen);
            puts(infoBuf);
            char titleBuf[1024] = {};
            sprintf(
                titleBuf,
                "ISPC Triangle Renderer  [%s] Controls: Move with WASD and "
                "Q/E, toggle wireframe "
                "with V, Change FOV "
                "with C/Z",
                infoBuf);
            if((frameIndex % 16) == 0) glfwSetWindowTitle(window, titleBuf);
        }
    }

    // glfw: terminate, clearing all previously allocated GLFW resources.
    glfwTerminate();
    return 0;
}

// Unity build
#include "glad/glad.c"