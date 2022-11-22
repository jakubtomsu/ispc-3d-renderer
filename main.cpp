#include <stdint.h>
#include <stdio.h>  // printf
#include <assert.h>
#include <stdlib.h>  // malloc
#include <string.h>  // memset
#include <glad/glad.h>
#include <glfw/glfw3.h>

#define staticArrayLen(arr) (sizeof(arr) / sizeof(arr[0]))

struct Context {
    int frameX;
    int frameY;
    uint8_t* frameImage;
};

static Context g_context = {};
#define FRAME_IMAGE_PIXEL_BYTES 4

// process all input: query GLFW whether relevant keys are pressed/released this frame and react accordingly
static void processInput(GLFWwindow* window) {
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);
}

static size_t getFrameImageSizeInBytes() {
    return FRAME_IMAGE_PIXEL_BYTES * g_context.frameX * g_context.frameY;
}

static void changeFrameSize(const int x, const int y) {
    if (x <= 0 || y <= 0) {
        return;
    }
    if (x == g_context.frameX && y == g_context.frameY) {
        return;
    }
    g_context.frameX = x;
    g_context.frameY = y;
    if (g_context.frameImage != nullptr) {
        free(g_context.frameImage);
    }
    g_context.frameImage = (uint8_t*)malloc(getFrameImageSizeInBytes());
    assert(g_context.frameImage != nullptr);
}

// glfw: whenever the window size changed (by OS or user resize) this callback function executes
static void framebufferSizeChangedGlfwCallback(GLFWwindow* window, int width, int height) {
    // make sure the viewport matches the new window dimensions; note that width and
    // height will be significantly larger than specified on retina displays.
    glViewport(0, 0, width, height);
}

static void GLAPIENTRY debugMessageOpenglCallback(GLenum source,
                                                  GLenum type,
                                                  GLuint id,
                                                  GLenum severity,
                                                  GLsizei length,
                                                  const GLchar* message,
                                                  const void* userParam) {
    printf("[OpenGl Error]: %s type = 0x%x, severity = 0x%x, message = %s\n",
           (type == GL_DEBUG_TYPE_ERROR ? "** GL ERROR **" : ""), type, severity, message);
}

static void uploadFrameImageToGpu(GLuint texture) {
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, g_context.frameX, g_context.frameY, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                 g_context.frameImage);
}

static inline uint8_t floatToUNorm8(const float value) {
    return (uint8_t)(value * 255.0f);
}
static void renderFrame() {
    assert(g_context.frameImage != nullptr);
    const int frameX = g_context.frameX;
    const int frameY = g_context.frameY;
    for (int x = 0; x < frameX; x++) {
        for (int y = 0; y < frameY; y++) {
            g_context.frameImage[(x + y * frameX) * FRAME_IMAGE_PIXEL_BYTES] = floatToUNorm8((float)x / (float)frameX);
        }
    }
}

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
    if (window == nullptr) {
        printf("[glfwCreateWindow] Failed to open a window.");
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebufferSizeChangedGlfwCallback);

    changeFrameSize(startWindowX, startWindowY);

    // glad: load all OpenGL function pointers
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
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
        if (!success) {
            glGetShaderInfoLog(vertShader, staticArrayLen(infoLog), nullptr, infoLog);
            printf("[glCompileShader] Vertex Shader Error: %s", infoLog);
            assert(false);
        }

        GLint fragShader = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fragShader, 1, &fragSource, nullptr);
        glCompileShader(fragShader);
        if (!success) {
            glGetShaderInfoLog(fragShader, staticArrayLen(infoLog), nullptr, infoLog);
            printf("[glCompileShader] Vertex Shader Error: %s", infoLog);
            assert(false);
        }

        shaderProgram = glCreateProgram();
        glAttachShader(shaderProgram, vertShader);
        glAttachShader(shaderProgram, fragShader);
        glLinkProgram(shaderProgram);
        glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success);
        if (!success) {
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
            -1.0f, -1.0f, 1.0f, -1.0f, -1.0f, 1.0f, -1.0f, 1.0f, 1.0f, -1.0f, 1.0f, 1.0f,
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
    glGenTextures(1, &frameTexture);
    glBindTexture(GL_TEXTURE_2D, frameTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    memset(g_context.frameImage, 127, getFrameImageSizeInBytes());
    uploadFrameImageToGpu(frameTexture);

    // render loop
    while (!glfwWindowShouldClose(window)) {
        processInput(window);

        int currentWindowX = 0;
        int currentWindowY = 0;
        glfwGetWindowSize(window, &currentWindowX, &currentWindowY);

        if (g_context.frameX != currentWindowX || g_context.frameY != currentWindowY) {
            changeFrameSize(currentWindowX, currentWindowY);
        }

        memset(g_context.frameImage, 0, getFrameImageSizeInBytes());
        renderFrame();
        uploadFrameImageToGpu(frameTexture);
        printf("[Frame] x:%i y:%i mem:%ib ptr:%p\n", g_context.frameX, g_context.frameY, getFrameImageSizeInBytes(),
               g_context.frameImage);

        // render
        glUseProgram(shaderProgram);
        glBindVertexArray(quadVao);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, frameTexture);
        glDrawArrays(GL_TRIANGLES, 0, 3 * 2);

        glfwSwapBuffers(window);
        glFlush();
        glfwPollEvents();
    }

    // glfw: terminate, clearing all previously allocated GLFW resources.
    glfwTerminate();
    return 0;
}

// Unity build
#include "glad/glad.c"