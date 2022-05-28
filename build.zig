const builds = @import("std").build;
const Builder = builds.Builder;
const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    // setup for raylib wasm build too, but right now zig doesn't fully support
    // the wasm C ABI, so passing structs by value doesn't work. This will be
    // fixed in the 0.10 release.

    // build raylib
    var libraylib = b.addStaticLibrary("raylib", null);
    const is_web_target = target.cpu_arch != null and target.cpu_arch.? == .wasm32;

    if (is_web_target) {
        libraylib.addIncludeDir("/home/nc/src/emsdk/upstream/emscripten/cache/sysroot/include/");
        libraylib.defineCMacro("PLATFORM_WEB", "1");
        libraylib.defineCMacro("GRAPHICS_API_OPENGL_ES2", "1");
    } else {
        libraylib.defineCMacro("PLATFORM_DESKTOP", "1");
        libraylib.addIncludeDir("raylib/src/external/glfw/include/");

        if (target.isWindows()) {
            libraylib.linkSystemLibrary("opengl32");
            libraylib.linkSystemLibrary("gdi32");
            libraylib.linkSystemLibrary("winmm");
        } else if (target.isLinux()) {
            libraylib.linkSystemLibrary("X11");
            libraylib.linkSystemLibrary("GL");
            libraylib.linkSystemLibrary("m");
            libraylib.linkSystemLibrary("pthread");
            libraylib.linkSystemLibrary("dl");
            libraylib.linkSystemLibrary("rt");
        }
        libraylib.linkLibC();
    }

    libraylib.addCSourceFile("raylib/src/rglfw.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/rcore.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/rshapes.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/rtextures.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/rtext.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/rmodels.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/utils.c", &.{"-fno-sanitize=undefined"});
    libraylib.addCSourceFile("raylib/src/raudio.c", &.{"-fno-sanitize=undefined"});
    libraylib.addIncludeDir("raylib/src");
    //std.fs.copyFileAbsolute(b.pathFromRoot("raygui/src/raygui.h"), b.pathFromRoot("raygui/src/raygui.c"), .{}) catch unreachable;
    //libraylib.addCSourceFile("raygui/src/raygui.c", &.{ "-fno-sanitize=undefined", "-DRAYGUI_IMPLEMENTATION" });
    libraylib.setTarget(target);
    libraylib.setBuildMode(mode);
    libraylib.install();

    const libgame = b.addStaticLibrary("game", "game.zig");
    libgame.setBuildMode(mode);
    libgame.setTarget(target);
    if (is_web_target) {
        libgame.addIncludeDir("/home/nc/src/emsdk/upstream/emscripten/cache/sysroot/include/");
    } else {
        libgame.linkLibC();
    }
    libgame.addIncludeDir("raylib/src");
    //libgame.addIncludeDir("raygui/src");
    libgame.install();

    if (is_web_target) {
        // `source ~/src/emsdk/emsdk_env.sh` first
        const emcc = b.addSystemCommand(&.{
            "emcc",
            "entry.c",
            "-g",
            //"-Os",
            //"--closure",
            //"1",
            "-ogame.html",
            "-Lzig-out/lib/",
            "-lgame",
            "-lraylib",
            "-sNO_FILESYSTEM=1",
            "-sFULL_ES3=1",
            "-sMALLOC='emmalloc'",
            "-sASSERTIONS=0",
            "-sUSE_GLFW=3",
            "-sSTANDALONE_WASM",
            "-sEXPORTED_FUNCTIONS=['_malloc','_free','_main']",
            //"-g",
            //"-o",
            //"game.html",
            //"-Os",
            ////"--closure", "1",
            //"entry.c",
            //"-Lzig-out/lib/",
            //"-lgame",
            //"-lraylib",
            //"-s",
            //"USE_GLFW=3",
            //"-sMALLOC='emmalloc'",
            ////"-sNO_FILESYSTEM=1",
            ////"-sMALLOC='emmalloc'",
            ////"-sASSERTIONS=0",
            //"-sEXPORTED_FUNCTIONS=['_malloc','_free','_main']",
        });

        emcc.step.dependOn(&libraylib.install_step.?.step);
        emcc.step.dependOn(&libgame.install_step.?.step);

        b.getInstallStep().dependOn(&emcc.step);
    } else {
        const game = b.addExecutable("game", "_desktop_entry.zig");
        game.addIncludeDir("raylib/src");
        //game.addIncludeDir("raygui/src");
        game.linkLibrary(libraylib);
        game.linkLibrary(libgame);
        //game.linkSystemLibrary("glfw");
        game.linkLibC();
        game.install();
    }

    //const run_cmd = exe.run();
    //run_cmd.step.dependOn(b.getInstallStep());

    //const run_step = b.step("run", "Run the app");
    //run_step.dependOn(&run_cmd.step);
}
