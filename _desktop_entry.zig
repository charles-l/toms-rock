const c = @cImport({
    @cInclude("raylib.h");
});
const game = @import("game.zig");

pub fn main() void {
    c.InitWindow(game.screenWidth, game.screenHeight, "Tom's Rock");
    c.InitAudioDevice();
    game.init();
    c.SetTargetFPS(60);
    while (!c.WindowShouldClose()) {
        game.renderFrame();
    }
    c.CloseAudioDevice();
    c.CloseWindow();
}
