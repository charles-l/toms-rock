const c = @cImport({
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLES3/gl3.h");
    @cInclude("math.h");
    @cInclude("stdlib.h");
    @cInclude("emscripten.h");
});
const assert = @import("std").debug.assert;

var program: ?c_uint = null;

var counter: usize = 0;

const PI = 3.14159;

fn onDraw(arg: *anyopaque) void {
    _ = arg;

    const color = [_]c_uint{ 255, 0, 0, 0, 255, 0, 0, 0, 255 };
    var location = @intCast(c_uint, c.glGetAttribLocation(program.?, "aColor"));
    c.glVertexAttribIPointer(location, 3, c.GL_UNSIGNED_INT, 0, &color);
    c.glEnableVertexAttribArray(location);

    const t: f32 = @intToFloat(f32, counter) / 60.0;
    const r: f32 = 0.5 + c.sinf(t / 8) / 4;
    const s: f32 = t / 4;
    const position = [_]f32{ r * c.sinf(s), r * c.cosf(s), r * c.sinf(s + 2.0 * PI / 3.0), r * c.cosf(s + 2.0 * PI / 3.0), r * c.sinf(s + 4.0 * PI / 3.0), r * c.cosf(s + 4.0 * PI / 3.0) };
    location = @intCast(c_uint, c.glGetAttribLocation(program.?, "aPosition"));
    c.glVertexAttribPointer(location, 2, c.GL_FLOAT, c.GL_FALSE, 0, &position);
    c.glEnableVertexAttribArray(location);

    c.glClear(c.GL_COLOR_BUFFER_BIT);
    c.glDrawArrays(c.GL_TRIANGLES, 0, 3);

    counter += 1;
}

export fn run_zig() void {
    if (c.glfwInit() == 0) {
        return;
    }
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_OPENGL_ES_API);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 0);
    var window = c.glfwCreateWindow(500, 500, "Client-side Vertex Arrays", null, null);
    if (window == null) {
        c.glfwTerminate();
        return;
    }
    c.glfwMakeContextCurrent(window);

    const vertex_source: [*]const u8 = // waka
        \\#version 300 es
        \\
        \\in vec2 aPosition;
        \\in uvec3 aColor;
        \\out vec4 color;
        \\
        \\void main() {
        \\   gl_Position = vec4(aPosition, 0.f, 1.f);
        \\   color = vec4(vec3(aColor) / 255.f, 1.f);
        \\}
    ;
    const vertex_shader = c.glCreateShader(c.GL_VERTEX_SHADER);
    c.glShaderSource(vertex_shader, 1, &vertex_source, null);
    c.glCompileShader(vertex_shader);
    const fragment_source: [*]const c.GLchar =
        \\#version 300 es
        \\
        \\precision mediump float;
        \\
        \\in vec4 color;
        \\out vec4 FragColor;
        \\
        \\void main() {
        \\  FragColor = color;
        \\}
    ;
    const fragment_shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(fragment_shader, 1, &fragment_source, null);
    c.glCompileShader(fragment_shader);
    program = c.glCreateProgram();
    c.glAttachShader(program.?, vertex_shader);
    c.glAttachShader(program.?, fragment_shader);
    c.glLinkProgram(program.?);
    c.glUseProgram(program.?);

    while (true) {
        onDraw(&window);
        c.emscripten_sleep(0);
    }
}
