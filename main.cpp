#include <stdint.h>
#include <stdio.h>
#include <assert.h>
#include <glad/glad.h>
#include <glfw/glfw3.h>

#define SCR_WIDTH 800
#define SCR_HEIGHT 600

#define staticArrayLen(arr) (sizeof(arr) / sizeof(arr[0]))

// process all input: query GLFW whether relevant keys are pressed/released this frame and react accordingly
void processInput(GLFWwindow* window) {
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);
}

// glfw: whenever the window size changed (by OS or user resize) this callback function executes
void framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    // make sure the viewport matches the new window dimensions; note that width and
    // height will be significantly larger than specified on retina displays.
    glViewport(0, 0, width, height);
}

void GLAPIENTRY openglDebugCallback(GLenum source,
                                    GLenum type,
                                    GLuint id,
                                    GLenum severity,
                                    GLsizei length,
                                    const GLchar* message,
                                    const void* userParam) {
    printf("[OpenGl Error]: %s type = 0x%x, severity = 0x%x, message = %s\n",
           (type == GL_DEBUG_TYPE_ERROR ? "** GL ERROR **" : ""), type, severity, message);
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

    // glfw window creation
    GLFWwindow* window = glfwCreateWindow(SCR_WIDTH, SCR_HEIGHT, "ISPC software rasterizer", nullptr, nullptr);
    if (window == nullptr) {
        printf("[glfwCreateWindow] Failed to open a window.");
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);

    // glad: load all OpenGL function pointers
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        printf("[gladLoadGLLoader] Failed to load OpenGl function pointers.");
        return -1;
    }

    glEnable(GL_DEBUG_OUTPUT);
    glDebugMessageCallback(openglDebugCallback, 0);

    // Compile Shaders
    GLint shaderProgram;
    {
        const char* vertSource =
            "#version 460 core\n"
            "layout(location = 0) in vec2 in_pos;\n"
            "void main() { gl_Position = vec4(in_pos.x, in_pos.y, 0.0f, 1.0f); }\n";

        const char* fragSource =
            "#version 460 core\n"
            "layout(location = 0) out vec4 out_fragColor;\n"
            "void main() { out_fragColor = vec4(0.5f, 0.5f, 0.5f, 1.0f); }\n";

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
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindVertexArray(0);
    }

    glClearColor(0.2f, 0.3f, 0.3f, 1.0f);

    // render loop
    while (!glfwWindowShouldClose(window)) {
        processInput(window);

        // render
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(shaderProgram);
        glBindVertexArray(quadVao);
        glDrawArrays(GL_TRIANGLES, 0, 3 * 2);

        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    // glfw: terminate, clearing all previously allocated GLFW resources.
    glfwTerminate();
    return 0;
}

// Unity build
#include "glad/glad.c"