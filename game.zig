const c = @import("common.zig").c;

const m = @import("raymath.zig");

const builtin = @import("builtin");

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const clamp = std.math.clamp;

const is_web_target = (builtin.target.cpu.arch == .wasm32);

pub const screenWidth = 800;
pub const screenHeight = 600;

// wasm entrypoint
export fn web_main() void {
    if (is_web_target) {
        const cwasm = @cImport({
            @cInclude("emscripten/emscripten.h");
        });
        c.InitWindow(screenWidth, screenHeight, "Tom's Rock");
        init();
        cwasm.emscripten_set_main_loop(renderFrame, 0, 1);
        c.CloseWindow();
    }
}

const Enemy = struct {
    const ShieldStatus = enum {
        off,
        warning,
        on,
    };
    pos: m.Vector2,
    time: f32,
    vel: m.Vector2 = .{ .x = 0, .y = 0 },
    orbit_dir: f32 = 1,
    drop_prob: f32 = 0.006,
    shield_pattern: []const f32 = ([_]f32{ 3, 6, 9 })[0..],

    extractor: ?usize = null,

    const frame_times = [_]f32{ 3.0, 3.2, 4.0 };

    const Self = @This();

    fn shieldTime(self: Self) f32 {
        return @mod(self.time, self.shield_pattern[self.shield_pattern.len - 1]);
    }

    fn shieldStatus(self: Self) ShieldStatus {
        const cur_time = self.shieldTime();
        var ii: usize = 0;
        for (self.shield_pattern) |t, i| {
            if (cur_time < t) {
                ii = i;
                break;
            }
        }
        return switch (ii % 3) {
            0 => .off,
            1 => .warning,
            2 => .on,
            else => unreachable,
        };
    }

    fn addTime(self: *Self, t: f32) void {
        self.time += t;
    }

    fn frame(self: Self) usize {
        var ii: usize = 0;
        const cur_time = @mod(self.time, frame_times[frame_times.len - 1]);
        for (frame_times) |t, i| {
            if (t > cur_time) {
                ii = i;
                break;
            }
        }
        return ii;
    }
};

fn InPlaceArrayList(comptime T: type) type {
    return struct {
        data: std.ArrayList(T),
        free_mask: std.ArrayList(bool),

        const Self = @This();

        const Iterator = struct {
            list: *const Self,
            i: i32 = -1,

            fn next(self: *Iterator) ?T {
                assert(self.list.data.items.len == self.list.free_mask.items.len);

                self.i += 1;
                while (self.i < self.list.data.items.len and self.list.free_mask.items[@intCast(usize, self.i)]) {
                    self.i += 1;
                }

                if (0 <= self.i and self.i < self.list.data.items.len) {
                    return self.list.data.items[@intCast(usize, self.i)];
                } else {
                    return null;
                }
            }
        };

        fn get(self: Self, i: usize) ?T {
            if (self.free_mask.items[i]) {
                return null;
            } else {
                return self.data.items[i];
            }
        }

        fn iterator(self: Self) Iterator {
            return .{ .list = &self };
        }

        fn remove(self: Self, i: usize) T {
            self.free_mask.items[i] = true;
            return self.data.items[i];
        }

        fn add(self: *Self, val: T) usize {
            var free_i: ?usize = null;
            for (self.free_mask.items) |is_free, i| {
                if (is_free) {
                    free_i = i;
                    break;
                }
            }

            if (free_i) |i| {
                self.data.items[i] = val;
                self.free_mask.items[i] = false;
                return i;
            } else {
                self.data.append(val) catch {};
                self.free_mask.append(false) catch {};
                return self.data.items.len - 1;
            }
        }

        fn clearRetainingCapacity(self: *Self) void {
            self.data.clearRetainingCapacity();
            self.free_mask.clearRetainingCapacity();
        }

        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .data = std.ArrayList(T).init(allocator),
                .free_mask = std.ArrayList(bool).init(allocator),
            };
        }

        fn clone(self: *Self) !Self {
            return Self{
                .data = try self.data.clone(),
                .free_mask = try self.free_mask.clone(),
            };
        }

        fn deinit(self: Self) void {
            self.data.deinit();
            self.free_mask.deinit();
        }
    };
}

const BossState = enum {
    screech,
    idle,
    swoop_grab,
    hold,
    lasers,
    dead,
};

const boss_foot_offset = m.Vector2{ .x = -20, .y = 56 };

const State = struct {
    tail_pos_storage: [13]m.Vector2 = [_]m.Vector2{
        .{ .x = 395.1, .y = 203.5 },
        .{ .x = 386.1, .y = 208.0 },
        .{ .x = 379.9, .y = 216.0 },
        .{ .x = 378.0, .y = 225.8 },
        .{ .x = 380.7, .y = 235.5 },
        .{ .x = 387.4, .y = 243.0 },
        .{ .x = 396.7, .y = 246.8 },
        .{ .x = 406.8, .y = 245.9 },
        .{ .x = 415.4, .y = 240.7 },
        .{ .x = 420.8, .y = 232.2 },
        .{ .x = 421.8, .y = 222.2 },
        .{ .x = 418.3, .y = 212.8 },
        .{ .x = 411.0, .y = 205.9 },
    },

    old_tail_pos_storage: [13]m.Vector2 = [_]m.Vector2{
        .{ .x = 395.1, .y = 203.5 },
        .{ .x = 386.1, .y = 208.0 },
        .{ .x = 379.9, .y = 216.0 },
        .{ .x = 378.0, .y = 225.8 },
        .{ .x = 380.7, .y = 235.5 },
        .{ .x = 387.4, .y = 243.0 },
        .{ .x = 396.7, .y = 246.8 },
        .{ .x = 406.8, .y = 245.9 },
        .{ .x = 415.4, .y = 240.7 },
        .{ .x = 420.8, .y = 232.2 },
        .{ .x = 421.8, .y = 222.2 },
        .{ .x = 418.3, .y = 212.8 },
        .{ .x = 411.0, .y = 205.9 },
    },

    tail_pos: []m.Vector2,
    tail_old_pos: []m.Vector2,
    expression: enum {
        neutral,
        angry,
        irritated,
        eye_closed,
        eye_squeezed_closed,
    },
    boss: ?struct {
        position: c.Vector2,
        state: BossState,
        hold_l: ?u32,
        hold_r: ?u32,
        health: u32,
        state_time: f32,
        i: usize,
    },
    enemies: std.BoundedArray(Enemy, 64),
    lasers: std.BoundedArray([2]m.Vector2, 32),
    lasers_rot: f32,
    lasers_rot_speed: f32,
    extractors: InPlaceArrayList(m.Vector2),
    planet_health: f32,
    zapped_time_left: f32,
    current_level: usize,

    const Self = @This();

    fn clone(self: *Self) Self {
        var r = self.*;
        // FIXME: use a bounded array for this too
        r.extractors = self.extractors.clone() catch @panic("couldn't clone");
        return r;
    }

    fn deinit(self: *Self) void {
        self.extractors.deinit();
    }
};

fn resetPosition() void {
    for (state.tail_pos_storage) |*p, i| {
        const theta = @intToFloat(f32, i) * std.math.pi / 10 - std.math.pi / 2.0;
        p.* = m.Vector2Add(c.Vector2{
            .x = @cos(theta) * (planet_radius + player_radius),
            .y = @sin(theta) * (planet_radius + player_radius),
        }, center);
        state.old_tail_pos_storage[i] = p.*;
    }
}

fn bossStep() void {
    assert(boss_steps.len > 0);
    var boss_data = &state.boss.?;
    boss_data.i = (boss_data.i + 1) % boss_steps.len;
    setBossState(boss_steps[boss_data.i]);
}

fn setBossState(boss_state: BossState) void {
    prev_boss_state = state.boss.?.state;
    state.boss.?.state = boss_state;
    state.boss.?.state_time = 0;
}

const SpriteSheet = struct {
    texture: c.Texture,
    frames: usize,

    const Self = @This();
    fn width(self: Self) f32 {
        return @intToFloat(f32, self.texture.width) / @intToFloat(f32, self.frames);
    }

    fn frameRect(self: Self, i: usize) c.Rectangle {
        return c.Rectangle{
            .x = self.width() * @intToFloat(f32, i),
            .y = 0,
            .width = self.width(),
            .height = @intToFloat(f32, self.texture.height),
        };
    }

    fn drawFrameEx(self: Self, pos: m.Vector2, rotation: f32, i: usize, alpha: f32) void {
        c.DrawTexturePro(
            self.texture,
            self.frameRect(i),
            c.Rectangle{
                .x = pos.x,
                .y = pos.y,
                .width = self.width(),
                .height = @intToFloat(f32, self.texture.height),
            },
            m.Vector2{
                .x = self.width() / 2,
                .y = @intToFloat(f32, @divTrunc(self.texture.height, 2)),
            },
            radiansToDegrees(rotation),
            c.Color{ .r = 255, .g = 255, .b = 255, .a = @floatToInt(u8, 255 * alpha) },
        );
    }

    fn drawFrame(self: Self, pos: m.Vector2, rotation: f32, i: usize) void {
        self.drawFrameEx(pos, rotation, i, 1);
    }
};

// globals

var state: State = .{
    .tail_pos = &([0]m.Vector2{}),
    .tail_old_pos = &([0]m.Vector2{}),
    .expression = .eye_closed,
    .enemies = std.BoundedArray(Enemy, 64).init(0) catch unreachable,
    .lasers = std.BoundedArray([2]m.Vector2, 32).init(0) catch unreachable,
    .lasers_rot = 0,
    .lasers_rot_speed = 1,
    .extractors = InPlaceArrayList(m.Vector2).init(gpa.allocator()),
    .planet_health = 360,
    .zapped_time_left = 0,
    .current_level = 0,
    .boss = null,
};

var stars = [_]m.Vector2{.{ .x = 0, .y = 0 }} ** 40;

// assets
var mongoose: SpriteSheet = undefined;
var explosion: SpriteSheet = undefined;
var extractor: SpriteSheet = undefined;
var boss: SpriteSheet = undefined;
var boss_white: c.Texture = undefined;
var music: [5]c.Music = undefined;
var current_music: []c.Music = &([0]c.Music{});
var explosion_sound: c.Sound = undefined;
var big_explosion_sound: c.Sound = undefined;
var zap_sound: c.Sound = undefined;
var screech_sound: c.Sound = undefined;
var hit_sound: c.Sound = undefined;

var font: c.Font = undefined;
const font_size = 30;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var rand: std.rand.DefaultPrng = undefined;

const center = m.Vector2{ .x = screenWidth / 2, .y = screenHeight / 2 };
var planet_radius: f32 = 35;
const player_radius = 2;
const enemy_radius = 15;
const boss_radius = 55;
const GameplayState = enum {
    dead,
    alive,
    no_control,
};

var gameplay_state: GameplayState = .alive;

var coroutines: Coroutines = undefined;
var ui_tasks: Coroutines = undefined;

var fade_to_white: f32 = 0;

const CancelToken = struct {};

const levels = [_]fn (*CancelToken) callconv(.Async) void{
    level_1,
    level_2,
    level_3,
    level_4,
    level_5_intro,
    level_5,
};

var frame_i: u32 = 0;
var camera = c.Camera2D{
    .offset = .{ .x = screenWidth / 2, .y = screenHeight / 2 },
    .target = .{ .x = screenWidth / 2, .y = screenHeight / 2 },
    .rotation = 0,
    .zoom = 1,
};

var level_start_state: State = undefined;
const cancel_level = CancelToken{};

var boss_speed: f32 = 4;
var boss_steps: []const BossState = &([1]BossState{.idle});

pub fn init() void {
    c.HideCursor();
    mongoose = .{ .texture = c.LoadTexture("mongoose.png"), .frames = 3 };
    explosion = .{ .texture = c.LoadTexture("explosion.png"), .frames = 8 };
    extractor = .{ .texture = c.LoadTexture("extractor.png"), .frames = 1 };
    boss = .{ .texture = c.LoadTexture("laughing_falcon.png"), .frames = 8 };
    {
        // generate image (all white pixels) of boss with alpha cutout for final explosion
        var base_img = c.GenImageColor(@floatToInt(i32, boss.width()), boss.texture.height, c.WHITE);
        const img1 = c.LoadImageFromTexture(boss.texture);
        defer c.UnloadImage(img1);

        var img2 = c.ImageFromImage(img1, boss.frameRect(7));
        defer c.UnloadImage(img2);

        // update mask
        var pixels = c.LoadImageColors(img2);
        for (pixels[0..@intCast(usize, img2.width * img2.height)]) |*p| {
            if (p.a == 0) {
                p.r = 0;
                p.g = 0;
                p.b = 0;
            } else {
                p.a = 255;
                p.r = 255;
                p.g = 255;
                p.b = 255;
            }
        }
        c.UnloadImageColors(@ptrCast([*c]c.Color, img2.data));
        img2.data = pixels;

        c.ImageAlphaMask(&base_img, img2);
        boss_white = c.LoadTextureFromImage(base_img);
    }

    music = [_]c.Music{ c.LoadMusicStream("spacesnake_intro1.ogg"), c.LoadMusicStream("spacesnake_intro2.ogg"), c.LoadMusicStream("spacesnake.ogg"), c.LoadMusicStream("spacesnake_boss_intro.ogg"), c.LoadMusicStream("spacesnake_boss.ogg") };
    music[0].looping = true;
    music[1].looping = false;
    music[2].looping = true;
    music[3].looping = false;
    music[4].looping = true;
    explosion_sound = c.LoadSound("explosion.wav");
    big_explosion_sound = c.LoadSound("boss_final_explosion.ogg");
    zap_sound = c.LoadSound("zap.wav");
    screech_sound = c.LoadSound("screech.ogg");
    hit_sound = c.LoadSound("boss_hit.wav");

    //current_music = music[2..3];
    current_music = music[0..1];
    c.PlayMusicStream(current_music[0]);

    state.tail_pos = state.tail_pos_storage[0..];
    state.tail_old_pos = state.old_tail_pos_storage[0..];

    rand = std.rand.DefaultPrng.init(0);

    for (stars) |*pos| {
        pos.x = rand.random().float(f32) * screenWidth;
        pos.y = rand.random().float(f32) * screenHeight;
    }

    coroutines = Coroutines.init(gpa.allocator());
    ui_tasks = Coroutines.init(gpa.allocator());
    font = c.LoadFontEx("font/GamjaFlower-Regular.ttf", font_size, 0, 128);
}

fn drawTextEx(msg: [:0]const u8, pos: m.Vector2, tint: c.Color) void {
    for (msg) |char, i| {
        const s = [_]u8{ char, 0 };
        c.DrawTextPro(
            font,
            &s,
            .{ .x = pos.x + @intToFloat(f32, i) * 10 - (@intToFloat(f32, msg.len) * 10) / 2, .y = pos.y - font_size / 2 },
            .{ .x = 10, .y = 10 },
            @sin(@floor(@mod(@floatCast(f32, c.GetTime()), 8)) + @intToFloat(f32, i) * 14132) * 14,
            font_size,
            0,
            tint,
        );
    }
}

fn drawText(msg: [:0]const u8, pos: m.Vector2) void {
    drawTextEx(msg, pos, c.WHITE);
}

fn toi32(v: f32) i32 {
    return @floatToInt(i32, v);
}

fn verletIntegrate(pos: []m.Vector2, old_pos: []m.Vector2) void {
    assert(pos.len == old_pos.len);

    for (pos) |*p, i| {
        const gravity = m.Vector2Scale(subNorm(center, p.*), 0.4);
        //c.DrawLineV(p.*, m.Vector2Add(p.*, m.Vector2Scale(subNorm(center, p.*), 10)), c.GREEN);
        const tmp = p.*;
        p.* = m.Vector2Add(m.Vector2Add(p.*, m.Vector2Subtract(p.*, old_pos[i])), if (state.planet_health > 0) gravity else m.Vector2Zero());

        // HACK: clamp top speed so it can't phase through the planet
        const d = m.Vector2Subtract(tmp, pos[i]);
        if (m.Vector2Length(d) < planet_radius) {
            old_pos[i] = tmp;
        } else {
            old_pos[i] = m.Vector2Add(p.*, m.Vector2Scale(m.Vector2Normalize(d), 5));
        }
    }
}

fn lineCircleIntersection(p1: m.Vector2, p2: m.Vector2, circle_pos: m.Vector2, radius: f32) ?m.Vector2 {
    if (m.Vector2Distance(p1, circle_pos) < radius) {
        // already inside -- pop out by normal
        return m.Vector2Scale(subNorm(p1, circle_pos), radius);
    }

    const d = m.Vector2Subtract(p2, p1);
    const f = m.Vector2Subtract(p1, circle_pos);

    const a = m.Vector2DotProduct(d, d);
    const b = 2 * m.Vector2DotProduct(f, d);
    const _c = m.Vector2DotProduct(f, f) - radius * radius;

    var discriminant = b * b - 4 * a * _c;
    if (discriminant < 0) {
        return null;
    } else {
        discriminant = std.math.sqrt(discriminant);

        const t1 = (-b - discriminant) / (2 * a);
        const t2 = (-b + discriminant) / (2 * a);

        if (t1 >= 0 and t1 <= 1) {
            return m.Vector2Add(p1, m.Vector2Scale(d, t1));
        }

        if (t2 >= 0 and t2 <= 1) {
            return m.Vector2Add(p1, m.Vector2Scale(d, t2));
        }

        return null;
    }
}

fn getMoveInput() ?m.Vector2 {
    if (gameplay_state == .alive and c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT) and state.zapped_time_left <= 0) {
        const mouse_pos = m.Vector3{ .x = @intToFloat(f32, c.GetMouseX()), .y = @intToFloat(f32, c.GetMouseY()), .z = 0 };

        // lifted from raylib source code (GetScreenToWorld2D())

        const mat_camera: m.Matrix = c.GetCameraMatrix2D(camera);
        const inv_mat_camera: m.Matrix = m.MatrixInvert(mat_camera);
        const transform = m.Vector3Transform(mouse_pos, inv_mat_camera);

        return m.Vector2{ .x = transform.x, .y = transform.y };
    }
    return null;
}

fn getShouldShrinkInput() bool {
    return gameplay_state == .alive and state.zapped_time_left <= 0 and (c.IsMouseButtonDown(c.MOUSE_BUTTON_RIGHT) or c.IsKeyDown(c.KEY_SPACE));
}

fn tailLeft() usize {
    return state.tail_pos.len - 3;
}

const perms = [_]u8{ 151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180 };

inline fn hash(i: i32) u8 {
    return perms[@intCast(usize, i & 0xFF)];
}

fn grad(ihash: i32, x: f32) f32 {
    const h = ihash & 0x0F;
    var fgrad = 1.0 + @intToFloat(f32, h & 7);
    if ((h & 8) != 0) {
        fgrad = -fgrad;
    }
    return fgrad * x;
}

// 1d simplex noise
// ported from https://github.com/SRombauts/SimplexNoise/blob/master/src/SimplexNoise.cpp#L175
export fn noise(x: f32) f32 {
    // Corners
    const i_0: i32 = @floatToInt(i32, x);
    const i_1 = i_0 + 1;

    // Distance
    const x0 = x - @intToFloat(f32, i_0);
    const x1 = x0 - 1.0;

    var t0 = 1.0 - x0 * x0;
    t0 *= t0;

    const n0 = t0 * t0 * grad(hash(i_0), x0);

    var t1 = 1.0 - x1 * x1;
    t1 *= t1;
    const n1 = t1 * t1 * grad(hash(i_1), x1);

    // The maximum value of this noise is 8*(3/4)^4 = 2.53125
    // A factor of 0.395 scales to fit exactly within [-1,1]
    return 0.395 * (n0 + n1);
}

fn cameraShake(duration: f32, scale: f32) void {
    const orig_pos = camera.offset;
    const start_time = c.GetTime();
    while (c.GetTime() < start_time + duration) {
        camera.offset = m.Vector2Add(orig_pos, c.Vector2{ .x = noise(@floatCast(f32, c.GetTime()) * 20) * scale, .y = noise(@floatCast(f32, c.GetTime() + 50.7) * 20) * scale });
        suspend {
            coroutines.yield(@frame(), null);
        }
    }
    camera.offset = orig_pos;
}

fn verletSolveConstraints(pos: []m.Vector2) void {
    var i: u32 = 0;

    var snake_joint_dist: f32 = 10;
    if (getShouldShrinkInput()) {
        snake_joint_dist = 2;
    }

    while (i < pos.len - 1) : (i += 1) {
        var n1 = &pos[i];
        var n2 = &pos[i + 1];

        if (i == 0) {
            if (getMoveInput()) |input_pos| {
                var max = 0.1 + (@intToFloat(f32, numSnakeJointsOnGround()) / @intToFloat(f32, state.tail_pos.len)) * 5;
                if (getShouldShrinkInput()) {
                    max += 0.5;
                }
                n1.* = m.Vector2Add(n1.*, m.Vector2ClampValue(m.Vector2Subtract(input_pos, n1.*), 0, max));
            }
        }

        if (state.boss) |boss_data| {
            if (boss_data.state == .hold) {
                if (boss_data.hold_l) |joint_i| {
                    if (i == joint_i) {
                        n1.* = m.Vector2Add(boss_data.position, boss_foot_offset);
                    }
                }

                if (boss_data.hold_r) |joint_i| {
                    if (i == joint_i) {
                        n1.* = m.Vector2Add(boss_data.position, m.Vector2{ .x = -boss_foot_offset.x, .y = boss_foot_offset.y });
                    }
                }
            }
        }

        {
            var diff = m.Vector2Subtract(n1.*, n2.*);
            const dist = m.Vector2Length(diff);

            var difference: f32 = 0;
            if (dist > 0) {
                difference = (snake_joint_dist - dist) / dist;
            } else {
                difference = 1;
                diff = m.Vector2Add(m.Vector2{ .x = 0, .y = 1 }, n1.*);
            }

            if (i == 0) {
                // give slightly more pull to the head joint.
                const t1 = m.Vector2Scale(diff, 0.2 * difference);
                const t2 = m.Vector2Scale(diff, 0.8 * difference);
                n1.* = m.Vector2Add(n1.*, t1);
                n2.* = m.Vector2Subtract(n2.*, t2);
            } else {
                const translate = m.Vector2Scale(diff, 0.5 * difference);
                n1.* = m.Vector2Add(n1.*, translate);
                n2.* = m.Vector2Subtract(n2.*, translate);
            }
        }

        // adds more structure/stiffness by trying to keep nodes 2 steps apart
        // away from each other
        if (i < pos.len - 2) {
            var n3 = &pos[i + 2];
            {
                const diff = m.Vector2Subtract(n1.*, n3.*);
                const dist = m.Vector2Length(diff);

                var difference: f32 = 0;
                assert(dist != 0);
                difference = ((snake_joint_dist * 2) - dist) / dist;

                const translate = m.Vector2Scale(diff, 0.5 * difference);
                n1.* = m.Vector2Add(n1.*, m.Vector2Scale(translate, 0.1));
                n3.* = m.Vector2Subtract(n3.*, m.Vector2Scale(translate, 0.1));
            }
        }
    }
}

pub fn subNorm(a: m.Vector2, b: m.Vector2) m.Vector2 {
    return m.Vector2Normalize(m.Vector2Subtract(a, b));
}

pub fn subNormScale(a: m.Vector2, b: m.Vector2, f: f32) m.Vector2 {
    return m.Vector2Scale(m.Vector2Normalize(m.Vector2Subtract(a, b)), f);
}

pub fn vecClamp(v: m.Vector2, f: f32) m.Vector2 {
    const l = m.Vector2Length(v);
    if (l < f) {
        return v;
    } else {
        return m.Vector2Scale(v, f / l);
    }
}

fn vecAngle(v: m.Vector2) f32 {
    return std.math.atan2(f32, v.y, v.x) + std.math.pi / 2.0;
}

pub fn vecPerpClockwise(v: m.Vector2) m.Vector2 {
    return .{ .x = v.y, .y = -v.x };
}

pub fn subClamp(a: m.Vector2, b: m.Vector2, f: f32) m.Vector2 {
    var r = m.Vector2Subtract(a, b);
    const l = m.Vector2Length(r);
    if (l < f) {
        return r;
    } else {
        return m.Vector2Scale(r, f / l);
    }
}

fn snakeCollidingWith(enemy_pos: m.Vector2, radius: f32) bool {
    if (freezeFrame() or gameplay_state == .dead) {
        return false;
    }
    for (state.tail_pos) |p| {
        if (c.CheckCollisionCircles(p, player_radius, enemy_pos, radius)) {
            return true;
        }
    }
    return false;
}

const CircleCollision = struct {
    center: m.Vector2,
    radius: f32,
};

fn blockedCollision(pos: m.Vector2) ?CircleCollision {
    if (freezeFrame()) {
        return null;
    }
    if (state.boss) |b| {
        if (c.CheckCollisionCircles(pos, player_radius, b.position, boss_radius)) {
            return CircleCollision{ .center = b.position, .radius = boss_radius };
        }
    }
    if (state.planet_health > 0 and c.CheckCollisionCircles(pos, player_radius, center, planet_radius)) {
        return CircleCollision{ .center = center, .radius = planet_radius };
    }
    return null;
}

fn numSnakeJointsOnGround() u32 {
    var r: u32 = 0;
    for (state.tail_pos) |p| {
        if (blockedCollision(p)) |_| {
            r += 1;
        }
    }
    return r;
}

inline fn radiansToDegrees(rad: f32) f32 {
    return rad * (360.0 / (2.0 * std.math.pi));
}

const Coroutines = struct {
    const FramePair = struct { cancel_token: ?*CancelToken, frame: anyframe };

    allocator: std.mem.Allocator,
    frame_arena: std.heap.ArenaAllocator,
    frame_pointers: std.ArrayList(FramePair),

    const Self = @This();

    fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .frame_arena = std.heap.ArenaAllocator.init(allocator),
            .frame_pointers = std.ArrayList(FramePair).init(allocator),
        };
    }

    fn yield(self: *Self, fr: anytype, cancel_token: ?*CancelToken) void {
        const T = @typeInfo(@TypeOf(fr)).Pointer.child;
        var frame_ptr = self.frame_arena.allocator().create(T) catch unreachable;
        frame_ptr.* = fr.*;
        self.frame_pointers.append(.{ .cancel_token = cancel_token, .frame = frame_ptr }) catch @panic("couldn't push coroutine");
    }

    fn cancel(self: *Self, token: *CancelToken) void {
        var idxs = std.BoundedArray(usize, 32).init(0) catch unreachable;
        for (self.frame_pointers.items) |x, i| {
            if (x.cancel_token) |t| {
                if (t == token) {
                    idxs.append(i) catch {};
                }
            }
        }

        std.mem.reverse(usize, idxs.slice());

        for (idxs.slice()) |i| {
            // we don't need to free the frame we're pointing to since
            // it's in an arena that will auto clean up.
            _ = self.frame_pointers.swapRemove(i);
        }
    }

    fn resumeAll(self: *Self) void {
        // store the bytes for the current coroutines
        var cos = self.frame_pointers.clone() catch @panic("blarg");
        defer cos.clearAndFree(); // delete old coroutine frame pointers after we're done
        var old_frames = self.frame_arena;
        defer old_frames.deinit(); // delete old coroutine frames after we're done

        // set up the next batch of coroutines
        self.frame_pointers.clearRetainingCapacity();
        self.frame_arena = std.heap.ArenaAllocator.init(self.allocator);

        // run them all
        for (cos.items) |co| {
            resume co.frame;
        }
    }
};

fn wait(interval: f32, token: ?*CancelToken) void {
    var start = c.GetTime();
    while (c.GetTime() - start < interval) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }
}

fn freezeFrame() bool {
    return state.zapped_time_left > 1.8;
}

fn zap() void {
    // give 0.5 second window between zap times
    if (state.zapped_time_left < -0.5) {
        c.PlaySoundMulti(zap_sound);
        state.zapped_time_left = 2;
        if (tailLeft() > 0) {
            state.tail_pos = state.tail_pos[0 .. state.tail_pos.len - 1];
            state.tail_old_pos = state.tail_old_pos[0 .. state.tail_old_pos.len - 1];
        }
    }
}

fn callOnInterval(comptime f: fn () void, interval: f32) void {
    while (true) {
        var start = c.GetTime();
        while (true) {
            suspend {
                coroutines.yield(@frame());
            }
            if (c.GetTime() - start > interval) {
                break;
            }
        }
        f();
    }
}

pub fn waitForCondition(cond: fn () bool, token: ?*CancelToken) void {
    while (!cond()) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }
}

fn allEnemiesAreDead() bool {
    return state.enemies.slice().len == 0 and state.boss == null;
}

fn tween(val: *f32, target: f32, duration: f32, token: ?*CancelToken) void {
    var start = c.GetTime();
    var range = target - val.*;
    var original_val = val.*;
    while (c.GetTime() < start + duration) {
        var dist = (c.GetTime() - start) / duration;
        val.* = original_val + @floatCast(f32, (dist * range));
        suspend {
            coroutines.yield(@frame(), token);
        }
    }
}

pub fn drawTextUntilContinue(msg: [:0]const u8, token: *CancelToken) void {
    suspend {
        ui_tasks.yield(@frame(), token);
    }
    while (!c.IsKeyPressed(c.KEY_X)) {
        suspend {
            ui_tasks.yield(@frame(), token);
        }

        drawText(msg, .{ .x = screenWidth / 2, .y = screenHeight / 2 + 140 });
        drawText("(Press X to continue)", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 170 });
    }
}

pub fn level_1(token: *CancelToken) void {
    gameplay_state = .no_control;
    current_music = music[0..1];
    c.PlayMusicStream(current_music[0]);
    current_music[0].looping = true;
    c.SetMusicPitch(current_music[0], 1);

    camera.zoom = 2;
    state.expression = .eye_closed;
    drawTextUntilContinue("This is Tom.", token);
    drawTextUntilContinue("Tom likes to nap on his green rock.", token);

    current_music = &music;
    current_music[0].looping = false;

    wait(2, token);
    tween(&camera.zoom, 1, 2, token);

    state.enemies.append(.{ .pos = m.Vector2{ .x = screenWidth / 2, .y = screenHeight }, .time = 0, .shield_pattern = &([_]f32{ 1, 1 }) }) catch unreachable;

    drawTextUntilContinue("Stop the mongoose troop from sucking the planet dry!", token);

    gameplay_state = .alive;

    drawTextUntilContinue("Left click moves, right click (or SPACE) shrinks and increases speed.", token);

    var n_groups: u32 = 5;
    while (n_groups > 0) : (n_groups -= 1) {
        var i: u32 = 0;
        const t = rand.random().float(f32) * 2 * std.math.pi;
        var spawn_point = m.Vector2{
            .x = @cos(t) * (screenWidth + 20),
            .y = @sin(t) * (screenWidth + 20),
        };

        while (i < 5) : (i += 1) {
            state.enemies.append(.{ .pos = spawn_point, .time = 0, .shield_pattern = &([_]f32{ 1, 1 }) }) catch unreachable;
            wait(0.3, token);
        }
        wait(4, token);
    }

    waitForCondition(allEnemiesAreDead, token);
    drawTextUntilContinue("Victory!", token);
}

pub fn level_2(token: *CancelToken) void {
    state.lasers.append(.{
        m.Vector2Add(center, .{ .x = -40, .y = 140 }),
        m.Vector2Add(center, .{ .x = 40, .y = 140 }),
    }) catch unreachable;

    c.SetMusicPitch(current_music[0], 1);
    camera.zoom = 2;

    drawTextUntilContinue("Beware the lasers!", token);

    wait(2, token);
    tween(&camera.zoom, 1, 2, token);

    var n_groups: u32 = 5;
    while (n_groups > 0) : (n_groups -= 1) {
        wait(4, token);
        var i: u32 = 0;
        const t = rand.random().float(f32) * 2 * std.math.pi;
        var spawn_point = m.Vector2{
            .x = @cos(t) * (screenWidth + 20),
            .y = @sin(t) * (screenWidth + 20),
        };

        while (i < 3) : (i += 1) {
            state.enemies.append(.{ .pos = spawn_point, .time = 0, .shield_pattern = &([_]f32{ 1, 1 }) }) catch unreachable;
            wait(0.3, token);
        }
    }

    waitForCondition(allEnemiesAreDead, token);

    while (!c.IsKeyPressed(c.KEY_X)) {
        suspend {
            ui_tasks.yield(@frame(), token);
        }

        drawText("Victory!", .{ .x = screenWidth / 2, .y = screenHeight / 2 });
        drawText("Press X to continue", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 100 });
    }
}

pub fn level_3(token: *CancelToken) void {
    state.lasers.append(.{
        m.Vector2Add(center, .{ .x = 100, .y = 0 }),
        m.Vector2Add(center, .{ .x = 300, .y = 0 }),
    }) catch unreachable;

    state.lasers.append(.{
        m.Vector2Add(center, .{ .x = -100, .y = 0 }),
        m.Vector2Add(center, .{ .x = -300, .y = 0 }),
    }) catch unreachable;

    c.SetMusicPitch(current_music[0], 1);
    camera.zoom = 2;
    wait(2, token);
    tween(&camera.zoom, 1, 2, token);

    var n_groups: u32 = 5;
    while (n_groups > 0) : (n_groups -= 1) {
        wait(2, token);
        var i: u32 = 0;
        const t = rand.random().float(f32) * 2 * std.math.pi;
        var spawn_point = m.Vector2{
            .x = @cos(t) * (screenWidth + 20),
            .y = @sin(t) * (screenWidth + 20),
        };

        while (i < 5) : (i += 1) {
            state.enemies.append(.{ .pos = spawn_point, .time = 0, .shield_pattern = &([_]f32{ 1, 1 }) }) catch unreachable;
            wait(0.3, token);
        }
    }

    waitForCondition(allEnemiesAreDead, token);

    while (!c.IsKeyPressed(c.KEY_X)) {
        suspend {
            ui_tasks.yield(@frame(), token);
        }

        drawText("Victory!", .{ .x = screenWidth / 2, .y = screenHeight / 2 });
        drawText("Press X to continue", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 100 });
    }
}

pub fn level_4(token: *CancelToken) void {
    current_music = music[2..3];
    c.PlayMusicStream(current_music[0]);
    state.lasers.append(.{
        m.Vector2Add(center, .{ .x = -100, .y = 0 }),
        m.Vector2Add(center, .{ .x = -150, .y = 0 }),
    }) catch unreachable;

    state.lasers.append(.{
        m.Vector2Add(center, .{ .x = -250, .y = 0 }),
        m.Vector2Add(center, .{ .x = -500, .y = 0 }),
    }) catch unreachable;

    c.SetMusicPitch(current_music[0], 1);
    camera.zoom = 2;
    drawTextUntilContinue("Red mongooses zap too!", token);

    wait(2, token);
    tween(&camera.zoom, 1, 2, token);

    var n_groups: u32 = 5;
    while (n_groups > 0) : (n_groups -= 1) {
        wait(3, token);
        var i: u32 = 0;
        const t = rand.random().float(f32) * 2 * std.math.pi;
        var spawn_point = m.Vector2{
            .x = @cos(t) * (screenWidth + 20),
            .y = @sin(t) * (screenWidth + 20),
        };

        while (i < 2) : (i += 1) {
            state.enemies.append(.{
                .pos = spawn_point,
                .time = 6,
            }) catch unreachable;
            wait(0.3, token);
        }
    }

    waitForCondition(allEnemiesAreDead, token);

    while (!c.IsKeyPressed(c.KEY_X)) {
        suspend {
            ui_tasks.yield(@frame(), token);
        }

        drawText("Victory!", .{ .x = screenWidth / 2, .y = screenHeight / 2 });
        drawText("Press X to continue", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 100 });
    }
}

pub fn level_5_intro(token: *CancelToken) void {
    gameplay_state = .no_control;
    boss_speed = 0.5;
    const s1 = c.GetTime();
    while (c.GetTime() - s1 < 3) {
        c.SetMusicVolume(current_music[0], 1 - (@floatCast(f32, (c.GetTime() - s1) / 3)));
        suspend {
            coroutines.yield(@frame(), token);
        }
    }
    const s2 = c.GetTime();
    current_music = music[3..];
    c.PlayMusicStream(current_music[0]);
    state.lasers_rot_speed = 0;

    state.boss = .{
        .position = .{ .x = screenWidth / 2, .y = -120 },
        .state = .idle,
        .hold_l = null,
        .hold_r = null,
        .health = 64,
        .state_time = 0,
        .i = 0,
    };

    state.expression = .angry;

    // wait for right time in song
    while (c.GetTime() - s2 < 12) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }

    // intro screech
    setBossState(.screech);
}

pub fn level_5(token: *CancelToken) void {
    gameplay_state = .alive;
    boss_speed = 4;

    boss_steps = ([_]BossState{ .idle, .swoop_grab })[0..];
    while (state.boss.?.health > 40) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }

    // new phase
    setBossState(.screech);

    boss_steps = ([_]BossState{ .idle, .swoop_grab, .lasers })[0..];
    while (state.boss.?.health > 20) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }

    setBossState(.screech);

    // calling wait() here segfaults >_<
    const s1 = c.GetTime();
    while (s1 + 4 < c.GetTime()) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }

    {
        var j: u32 = 0;
        while (j < 16) : (j += 1) {
            var spawn_point = m.Vector2{
                .x = @cos(@floatCast(f32, c.GetTime()) + @intToFloat(f32, j * 20)) * (screenWidth + 20),
                .y = @sin(@floatCast(f32, c.GetTime()) + @intToFloat(f32, j * 20)) * (screenWidth + 20),
            };
            state.enemies.append(.{ .pos = spawn_point, .time = 0, .shield_pattern = &([_]f32{ 1, 1 }), .drop_prob = 0.0005 }) catch unreachable;
        }
    }

    const s2 = c.GetTime();
    while (s2 + 4 < c.GetTime()) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }

    {
        var j: u32 = 0;
        while (j < 5) : (j += 1) {
            var spawn_point = m.Vector2{
                .x = @cos(@floatCast(f32, c.GetTime()) + @intToFloat(f32, j * 20)) * (screenWidth + 20),
                .y = @sin(@floatCast(f32, c.GetTime()) + @intToFloat(f32, j * 20)) * (screenWidth + 20),
            };
            state.enemies.append(.{ .pos = spawn_point, .time = 0, .shield_pattern = &([_]f32{ 3, 6, 9 }), .drop_prob = 0.00001 }) catch unreachable;
        }
    }

    while (state.boss.?.state != .dead or state.boss.?.state_time < 2) {
        suspend {
            coroutines.yield(@frame(), token);
        }
    }

    for (state.enemies.slice()) |enemy| {
        _ = async playSprite(enemy.pos, explosion, 0.1);
        state.enemies.resize(0) catch unreachable;
        state.extractors.clearRetainingCapacity();
    }

    {
        var i: u32 = 16;
        const w = @intToFloat(f32, boss_white.width);
        const h = @intToFloat(f32, boss_white.height);
        c.PlaySoundMulti(big_explosion_sound);
        while (i > 0) : (i -= 1) {
            _ = async playSprite(.{
                .x = state.boss.?.position.x + rand.random().float(f32) * w - w / 2,
                .y = state.boss.?.position.y + rand.random().float(f32) * h - h / 2,
            }, explosion, 0.1);

            suspend {
                coroutines.yield(@frame(), token);
            }
        }
    }

    // fade out music and fade in white box
    const s3 = c.GetTime();
    const l = 1;
    while (c.GetTime() - s3 < l) {
        const pct = (@floatCast(f32, (c.GetTime() - s3) / l));
        c.SetMusicVolume(current_music[0], 1 - pct);
        fade_to_white = pct;
        suspend {
            coroutines.yield(@frame(), token);
        }
    }
    fade_to_white = 1;
    state.boss = null;

    while (!c.IsKeyPressed(c.KEY_X)) {
        suspend {
            ui_tasks.yield(@frame(), token);
        }

        drawTextEx("Press X to continue", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 100 }, c.BLACK);
    }
    fade_to_white = 0;
}

fn playSprite(pos: m.Vector2, sprite: SpriteSheet, frame_time: f32) void {
    var i: usize = 0;
    var t = c.GetTime();
    while (i < sprite.frames) {
        sprite.drawFrame(pos, 0, i);

        suspend {
            coroutines.yield(@frame(), null);
        }
        if (c.GetTime() - t > frame_time) {
            t = c.GetTime();
            i += 1;
        }
    }
}

fn getDownAngle(pos: m.Vector2) f32 {
    return vecAngle(m.Vector2Subtract(pos, center));
}

fn renderGameOver(token: *CancelToken) void {
    while (true) {
        suspend {
            ui_tasks.yield(@frame(), token);
        }
        drawText("Game over", center);
        drawText("Press R to restart", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 50 });
    }
}

fn run_levels() void {
    while (state.current_level < levels.len) {
        resetPosition();
        state.zapped_time_left = 0;
        state.lasers.resize(0) catch {};
        level_start_state = state.clone();
        var bytes: [1024]u8 align(64) = undefined;
        await @asyncCall(&bytes, {}, levels[state.current_level], .{cancel_level});
        state.current_level += 1;
        state.planet_health = state.planet_health + (360 - state.planet_health) * 0.3;
    }

    current_music = music[0..1];
    current_music[0].looping = true;
    c.SetMusicVolume(current_music[0], 1);
    c.PlayMusicStream(current_music[0]);

    camera.zoom = 1;
    _ = async tween(&camera.zoom, 3, 5, null);
    resetPosition();
    gameplay_state = .no_control;
    state.expression = .eye_closed;
    while (true) {
        c.BeginMode2D(camera);
        c.DrawTextPro(
            font,
            "z",
            .{ .x = state.tail_pos[0].x, .y = state.tail_pos[0].y - 10 },
            .{ .x = 0, .y = 0 },
            @sin(@floor(@mod(@floatCast(f32, c.GetTime()), 8)) + 14132) * 14,
            10,
            0,
            c.WHITE,
        );
        c.DrawTextPro(
            font,
            "z",
            .{ .x = state.tail_pos[0].x + 4, .y = state.tail_pos[0].y - 20 },
            .{ .x = 0, .y = 0 },
            @sin(@floor(@mod(@floatCast(f32, c.GetTime()), 8)) + 2 * 14132) * 14,
            12,
            0,
            c.WHITE,
        );
        c.DrawTextPro(
            font,
            "z",
            .{ .x = state.tail_pos[0].x + 8, .y = state.tail_pos[0].y - 30 },
            .{ .x = 0, .y = 0 },
            @sin(@floor(@mod(@floatCast(f32, c.GetTime()), 8)) + 3 * 14132) * 14,
            14,
            0,
            c.WHITE,
        );
        c.EndMode2D();
        suspend {
            ui_tasks.yield(@frame(), cancel_level);
        }
        drawText("They didn't bother Tom after that.", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 140 });
        drawText("Thanks for playing", .{ .x = screenWidth / 2, .y = screenHeight / 2 + 170 });
    }
}

fn focusBoss() void {
    // Kinda broken. Not sure why the offset doesn't go back to the center
    // of the screen
    _ = async tween(&camera.offset.y, camera.offset.y + 120, 0.4, null);
    _ = async tween(&camera.zoom, 1.4, 0.4, null);
    wait(1, null);
    _ = async tween(&camera.offset.y, screenHeight / 2, 0.4, null);
    _ = async tween(&camera.zoom, 1, 0.4, null);
}

var prev_boss_state: BossState = .idle;
pub export fn renderFrame() void {
    var prev_health = state.planet_health;

    const time = @floatCast(f32, c.GetTime());

    if (!c.IsMusicStreamPlaying(current_music[0])) {
        current_music = current_music[1..current_music.len];
        c.PlayMusicStream(current_music[0]);
    }
    c.UpdateMusicStream(current_music[0]);

    if (frame_i == 0) {
        _ = async run_levels();
    }

    if (gameplay_state != .dead and (tailLeft() == 0 or state.planet_health <= 0)) {
        gameplay_state = .dead;
        // enter game over
        coroutines.cancel(cancel_level);
        ui_tasks.cancel(cancel_level);

        c.SetMusicPitch(current_music[0], 0.5);

        if (tailLeft() == 0) {
            state.zapped_time_left = std.math.inf(f32);
        }

        _ = async cameraShake(0.3, 10);
        _ = async renderGameOver(cancel_level);
    }

    if (c.IsKeyPressed(c.KEY_R)) {
        // don't allow restart during the cutscene
        if (state.current_level != 4) {
            coroutines.cancel(cancel_level);
            ui_tasks.cancel(cancel_level);
            state.deinit();
            state = level_start_state.clone();
            _ = async run_levels();
            gameplay_state = .alive;
            c.SetMusicPitch(current_music[0], 1);
            fade_to_white = 0;
        }
    }

    if (gameplay_state == .alive) {
        if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) {
            state.expression = .angry;
        } else if (c.IsMouseButtonDown(c.MOUSE_BUTTON_RIGHT)) {
            state.expression = .eye_squeezed_closed;
        } else {
            state.expression = .irritated;
        }
    }

    {
        state.zapped_time_left -= c.GetFrameTime();
        if (!freezeFrame()) {
            verletIntegrate(state.tail_pos, state.tail_old_pos);
            {
                var i: u32 = 0;
                while (i < 10) : (i += 1) {
                    verletSolveConstraints(state.tail_pos);
                    for (state.tail_pos) |*p| {
                        if (blockedCollision(p.*)) |col| {
                            p.* = m.Vector2Add(col.center, m.Vector2Scale(subNorm(p.*, col.center), col.radius + player_radius));
                        }
                    }
                }

                for (state.tail_pos) |*p, j| {
                    // if it was colliding last frame too, apply some "friction"
                    if (blockedCollision(state.tail_old_pos[j])) |_| {
                        p.* = m.Vector2Add(p.*, m.Vector2Scale(m.Vector2Subtract(state.tail_old_pos[j], p.*), 0.4));
                        // clamp movement if it's small enough
                        if (m.Vector2Distance(p.*, state.tail_old_pos[j]) < 0.05) {
                            p.* = state.tail_old_pos[j];
                        }
                    }
                }
            }
        }
    }

    c.BeginDrawing();
    defer c.EndDrawing();

    c.ClearBackground(c.BLACK);

    c.BeginMode2D(camera);

    for (stars) |pos| {
        c.DrawCircleV(pos, 1, c.WHITE);
    }

    {
        // draw the extractors
        var it = state.extractors.iterator();
        while (it.next()) |pos| {
            extractor.drawFrame(pos, getDownAngle(pos), 0);
        }
    }

    if (state.planet_health > 0) {
        // draw planet
        const green_hsv = c.ColorToHSV(c.DARKGREEN);
        const brown_hsv = c.ColorToHSV(c.BROWN);
        var saturation = ((1 + state.planet_health) / 361);
        c.DrawCircle(
            toi32(center.x),
            toi32(center.y),
            planet_radius,
            c.ColorFromHSV(green_hsv.x, saturation, green_hsv.z),
        );
        c.DrawCircle(
            toi32(center.x),
            toi32(center.y),
            planet_radius - 4,
            c.ColorFromHSV(brown_hsv.x, saturation, brown_hsv.z),
        );
    }

    { // draw snake
        var i: u32 = 0;
        const draw_zapped = state.zapped_time_left > 1.5 or (state.zapped_time_left > 0 and @mod(state.zapped_time_left, 0.2) > 0.1);

        while (i < state.tail_pos.len - 1) : (i += 1) {
            // draw snake
            c.DrawCircleV(state.tail_pos[i], player_radius, if (draw_zapped) c.BLACK else c.YELLOW);
            c.DrawLineEx(state.tail_pos[i], state.tail_pos[i + 1], 5, if (draw_zapped) c.BLACK else c.GREEN);
            if (draw_zapped) {
                c.DrawLineEx(state.tail_pos[i], state.tail_pos[i + 1], 2, c.WHITE);
            }
        }
        if (state.zapped_time_left > 0) {
            state.expression = .eye_squeezed_closed;
        }
        // draw eyebrow
        var perp = vecPerpClockwise(subNorm(state.tail_pos[0], state.tail_pos[1]));
        if (m.Vector2DotProduct(perp, subNorm(state.tail_pos[0], center)) < -0.8) {
            perp = m.Vector2Scale(perp, -1);
        }
        switch (state.expression) {
            .eye_closed => {},
            .eye_squeezed_closed => {},
            else => {
                // draw eye
                c.DrawCircleV(m.Vector2Scale(m.Vector2Add(state.tail_pos[0], state.tail_pos[1]), 0.5), 2, c.BLACK);
            },
        }
        switch (state.expression) {
            .neutral => c.DrawLineEx(m.Vector2Add(m.Vector2Scale(perp, 4), state.tail_pos[0]), m.Vector2Add(perp, state.tail_pos[1]), 2, c.DARKGREEN),
            .angry => c.DrawLineEx(m.Vector2Add(perp, state.tail_pos[0]), m.Vector2Add(m.Vector2Scale(perp, 4), state.tail_pos[1]), 2, c.DARKGREEN),
            .irritated => c.DrawLineEx(m.Vector2Add(perp, state.tail_pos[0]), m.Vector2Add(perp, state.tail_pos[1]), 2, c.DARKGREEN),
            .eye_closed => {
                var d = subNorm(state.tail_pos[1], state.tail_pos[0]);
                c.DrawLineEx(
                    state.tail_pos[0],
                    m.Vector2Add(state.tail_pos[0], m.Vector2Scale(d, 7)),
                    1,
                    c.DARKGREEN,
                );
            },
            .eye_squeezed_closed => {
                var d = subNorm(state.tail_pos[1], state.tail_pos[0]);
                c.DrawLineEx(
                    state.tail_pos[0],
                    m.Vector2Add(state.tail_pos[0], m.Vector2Add(m.Vector2Scale(perp, 2), m.Vector2Scale(d, 7))),
                    1,
                    c.DARKGREEN,
                );
                c.DrawLineEx(
                    state.tail_pos[0],
                    m.Vector2Add(state.tail_pos[0], m.Vector2Add(m.Vector2Scale(perp, -2), m.Vector2Scale(d, 7))),
                    1,
                    c.DARKGREEN,
                );
            },
        }
    }

    { // enemies
        { // destroy enemies if they collide with snake
            var enemies_to_delete = std.BoundedArray(usize, 32).init(0) catch unreachable;
            for (state.enemies.slice()) |enemy, i| {
                if (snakeCollidingWith(enemy.pos, enemy_radius)) {
                    if (enemy.shieldStatus() == .on) {
                        zap();
                    } else {
                        enemies_to_delete.append(i) catch {};
                    }
                }
            }

            {
                var j: usize = enemies_to_delete.len;

                while (j > 0) {
                    // janky cuz zig is preventing int underflow when i = 0...
                    j -= 1;
                    const i = enemies_to_delete.constSlice()[j];
                    _ = async playSprite(state.enemies.slice()[i].pos, explosion, 0.1);
                    c.SetSoundPitch(explosion_sound, 0.9 + (rand.random().float(f32) * 0.2));
                    c.PlaySoundMulti(explosion_sound);
                    if (state.enemies.slice()[i].extractor) |extractor_i| {
                        _ = async playSprite(state.extractors.get(extractor_i).?, explosion, 0.1);
                        _ = state.extractors.remove(extractor_i);
                    }
                    _ = state.enemies.swapRemove(i);
                }
            }
        }

        // delete any that collide with snek boi while falling
        {
            var it = state.extractors.iterator();
            while (it.next()) |pos| {
                const d = m.Vector2Subtract(center, pos);
                if (m.Vector2Length(d) > planet_radius + 10) {
                    state.extractors.data.items[@intCast(usize, it.i)] = m.Vector2Add(m.Vector2ClampValue(d, 0, 10), pos);

                    if (snakeCollidingWith(pos, enemy_radius)) {
                        _ = state.extractors.remove(@intCast(usize, it.i));
                        for (state.enemies.slice()) |*e| {
                            if (e.*.extractor != null and e.*.extractor.? == it.i) {
                                e.*.extractor = null;
                                break;
                            }
                        }
                        break;
                    }
                } else {
                    // extractor on the planet
                    state.planet_health -= @floatCast(f32, c.GetFrameTime() * 5);
                }
            }
        }

        { // movement logic
            for (state.enemies.slice()) |*enemy, i| {
                const orbit_dist = 100.0 + @intToFloat(f32, i % 3) * 20;
                var goal = m.Vector2Add(center, subNormScale(enemy.*.pos, center, planet_radius + orbit_dist));
                const orbit_vec = vecPerpClockwise(subNormScale(center, enemy.*.pos, 2));
                { // add flee to goal
                    const closest_joint = lbl: {
                        const h = state.tail_pos[0];
                        const t = state.tail_pos[state.tail_pos.len - 1];
                        if (m.Vector2Distance(h, enemy.*.pos) < m.Vector2Distance(t, enemy.*.pos)) {
                            break :lbl h;
                        } else {
                            break :lbl t;
                        }
                    };

                    const diff = m.Vector2Subtract(enemy.*.pos, closest_joint);
                    var d = std.math.clamp(m.Vector2Length(diff), 0, 100) / 100;

                    const move_force = lbl: {
                        if (enemy.*.extractor == null) {
                            break :lbl @as(f32, 100.0);
                        } else {
                            break :lbl @as(f32, 10.0);
                        }
                    };

                    goal = m.Vector2Add(goal, m.Vector2Scale(subNorm(
                        enemy.*.pos,
                        diff,
                    ), -(1 - d) * move_force));

                    // FIXME: flip logic is borked, but it's doing something for the movement right now so I'm leaving it.
                    if (m.Vector2DotProduct(m.Vector2Normalize(diff), m.Vector2Normalize(orbit_vec)) > 0.4 and m.Vector2Length(diff) < 80) {
                        //c.DrawTextEx(c.GetFontDefault(), "flip", m.Vector2Add(enemy.*.pos, .{ .x = 20, .y = 20 }), 10, 1, c.WHITE);
                        enemy.*.orbit_dir = -enemy.*.orbit_dir;
                    }
                }

                if (enemy.*.extractor == null and rand.random().float(f32) < enemy.drop_prob) {
                    enemy.*.extractor = state.extractors.add(enemy.*.pos);
                }

                // add orbit
                goal = m.Vector2Add(goal, m.Vector2Scale(orbit_vec, enemy.*.orbit_dir));

                //c.DrawCircleV(goal, 2, c.PURPLE);
                var goal_vel = subClamp(goal, enemy.*.pos, 8);
                var steering = subClamp(goal_vel, enemy.*.vel, 1);
                enemy.*.vel = vecClamp(m.Vector2Add(enemy.*.vel, steering), 10);
                enemy.*.pos = m.Vector2Add(enemy.*.pos, enemy.*.vel);
            }
        }

        // draw enemies
        for (state.enemies.slice()) |*e| {
            const d = m.Vector2Subtract(e.*.pos, center);

            e.*.addTime(c.GetFrameTime());

            c.DrawCircleLines(@floatToInt(i32, e.*.pos.x), @floatToInt(i32, e.*.pos.y), 10, c.WHITE);
            const rot = std.math.atan2(f32, d.y, d.x) + (std.math.pi / 2.0);
            if (e.*.extractor) |i| {
                const extractor_pos = state.extractors.data.items[i];
                const ext_d = m.Vector2Subtract(extractor_pos, center);
                // draw line connecting to extractor
                c.DrawLineV(e.*.pos, m.Vector2Add(extractor_pos, m.Vector2Scale(m.Vector2Normalize(ext_d), 10)), c.GRAY);
            } else {
                // draw inactive extractor
                extractor.drawFrame(m.Vector2Add(m.Vector2Scale(m.Vector2Normalize(d), -5), e.*.pos), rot, 0);
            }
            mongoose.drawFrame(e.*.pos, rot, e.*.frame());
            switch (e.shieldStatus()) {
                .off => {},
                .warning => c.DrawCircleGradient(
                    @floatToInt(i32, e.*.pos.x),
                    @floatToInt(i32, e.*.pos.y),
                    10 * (e.shieldTime() - 3) / 2,
                    c.ColorAlpha(c.YELLOW, 0.3),
                    c.ColorAlpha(c.YELLOW, 0.8),
                ),
                .on => c.DrawCircleGradient(
                    @floatToInt(i32, e.*.pos.x),
                    @floatToInt(i32, e.*.pos.y),
                    enemy_radius,
                    c.ColorAlpha(c.RED, 0.3),
                    c.ColorAlpha(c.RED, 0.8),
                ),
            }
        }

        if (state.boss) |*boss_data| {
            var goal = m.Vector2{ .x = screenWidth / 2, .y = 90 + @sin(time) * 20 };
            // HACK: clear out lasers every frame to make them immediate mode.
            state.lasers.resize(0) catch unreachable;
            boss_data.state_time += c.GetFrameTime();
            switch (boss_data.state) {
                .idle => {
                    const frame_time = 0.2;
                    const idle_frames = 4;
                    const f = @floatToInt(usize, @mod(time, idle_frames * frame_time) / frame_time);
                    boss.drawFrame(boss_data.position, 0, f);

                    if (boss_data.state_time > 4) {
                        bossStep();
                    }
                },
                .swoop_grab => {
                    if (prev_boss_state != .swoop_grab) {
                        prev_boss_state = .swoop_grab;
                        boss_data.hold_l = null;
                        boss_data.hold_r = null;
                    }
                    goal = m.Vector2Subtract(state.tail_pos[0], boss_foot_offset);
                    boss.drawFrame(boss_data.position, 0, 4);
                    const foot_pos_l = m.Vector2Add(boss_data.position, boss_foot_offset);
                    const foot_pos_r = m.Vector2Add(boss_data.position, m.Vector2{ .x = -boss_foot_offset.x, .y = boss_foot_offset.y });
                    for (state.tail_pos) |p, joint_i| {
                        if (m.Vector2Distance(p, foot_pos_l) < 40) {
                            c.DrawCircleLines(@floatToInt(i32, foot_pos_l.x), @floatToInt(i32, foot_pos_l.y), m.Vector2Distance(p, foot_pos_l), c.WHITE);
                            if (m.Vector2Distance(p, foot_pos_l) < 4) {
                                boss_data.hold_l = @intCast(u32, joint_i);
                                setBossState(.hold);
                                break;
                            }
                        }

                        if (m.Vector2Distance(p, foot_pos_r) < 40) {
                            c.DrawCircleLines(@floatToInt(i32, foot_pos_r.x), @floatToInt(i32, foot_pos_r.y), m.Vector2Distance(p, foot_pos_r), c.WHITE);
                            if (m.Vector2Distance(p, foot_pos_r) < 4) {
                                boss_data.hold_r = @intCast(u32, joint_i);
                                setBossState(.hold);
                                break;
                            }
                        }
                    }

                    if (boss_data.state_time > 4) {
                        bossStep();
                    }
                },
                .hold => {
                    if (prev_boss_state != .hold) {
                        prev_boss_state = .hold;
                        boss_data.state_time = 0;

                        {
                            // spawn enemies
                            var i: u32 = 0;
                            while (i < 3) : (i += 1) {
                                var spawn_point = m.Vector2{
                                    .x = @cos(time + @intToFloat(f32, i * 20)) * (screenWidth + 20),
                                    .y = @sin(time + @intToFloat(f32, i * 20)) * (screenWidth + 20),
                                };
                                state.enemies.append(.{ .pos = spawn_point, .time = 0, .shield_pattern = &([_]f32{ 1, 1 }) }) catch unreachable;
                            }
                        }
                    }
                    boss.drawFrame(boss_data.position, 0, 5);

                    if (boss_data.state_time > 4) {
                        bossStep();
                    }
                },
                .screech => {
                    // on enter
                    if (prev_boss_state != .screech) {
                        prev_boss_state = .screech;
                        _ = async focusBoss();
                        c.PlaySoundMulti(screech_sound);
                    }
                    boss.drawFrame(boss_data.position, 0, 6);

                    if (boss_data.state_time > 2) {
                        bossStep();
                    }
                },
                .lasers => {
                    const eye_level = m.Vector2Add(boss_data.position, .{ .x = 0, .y = -25 });
                    state.lasers.append(.{
                        m.Vector2Add(eye_level, .{ .x = -23, .y = 0 }),
                        m.Vector2Add(eye_level, .{ .x = -32 - @sin((boss_data.state_time + 2) * 3) * 40, .y = 150 }),
                    }) catch unreachable;
                    state.lasers.append(.{
                        m.Vector2Add(eye_level, .{ .x = 23, .y = 0 }),
                        m.Vector2Add(eye_level, .{ .x = 32 + @sin((boss_data.state_time + 2) * 3) * 40, .y = 150 }),
                    }) catch unreachable;
                    boss.drawFrame(boss_data.position, 0, 4);
                    if (boss_data.state_time > 3) {
                        bossStep();
                    }
                    c.DrawCircleV(eye_level, 10, c.RED);
                },
                .dead => {
                    if (prev_boss_state != .dead) {
                        prev_boss_state = .dead;
                        _ = async focusBoss();
                        c.PlaySoundMulti(screech_sound);
                    }
                    if (boss_data.state_time > 2) {
                        c.DrawTexture(
                            boss_white,
                            @floatToInt(i32, boss_data.position.x - @intToFloat(f32, boss_white.width) / 2),
                            @floatToInt(i32, boss_data.position.y - @intToFloat(f32, boss_white.height) / 2),
                            c.WHITE,
                        );
                    } else {
                        boss.drawFrame(boss_data.position, 0, 7);
                    }
                },
            }

            boss_data.position = m.Vector2Add(boss_data.position, vecClamp(m.Vector2Subtract(
                goal,
                boss_data.position,
            ), boss_speed));

            const left_engine = m.Vector2{ .x = boss_data.position.x - 50, .y = boss_data.position.y + 20 };
            const right_engine = m.Vector2{ .x = boss_data.position.x + 50, .y = boss_data.position.y + 20 };

            //c.DrawCircleLines(@floatToInt(i32, boss_data.position.x), @floatToInt(i32, boss_data.position.y), boss_radius, c.PURPLE);
            //c.DrawCircleLines(@floatToInt(i32, left_engine.x), @floatToInt(i32, left_engine.y), enemy_radius, c.PURPLE);
            //c.DrawCircleLines(@floatToInt(i32, right_engine.x), @floatToInt(i32, right_engine.y), enemy_radius, c.PURPLE);

            if (boss_data.state != .dead) {
                if (snakeCollidingWith(left_engine, enemy_radius)) {
                    _ = async playSprite(left_engine, explosion, 0.1);
                    boss_data.position.x += 30;
                    boss_data.health -= 1;
                    c.PlaySoundMulti(hit_sound);
                }

                if (snakeCollidingWith(right_engine, enemy_radius)) {
                    _ = async playSprite(right_engine, explosion, 0.1);
                    boss_data.position.x -= 30;
                    boss_data.health -= 1;
                    c.PlaySoundMulti(hit_sound);
                }

                if (boss_data.health < 2) {
                    setBossState(.dead);
                }
            }
        }
    }

    // rotate lasers
    state.lasers_rot += c.GetFrameTime();
    // draw lasers
    for (state.lasers.slice()) |l| {
        var l0 = l[0];
        var l1 = l[1];

        if (state.lasers_rot_speed != 0) {
            l0 = m.Vector2Add(center, m.Vector2Rotate(m.Vector2Subtract(l[0], center), state.lasers_rot));
            l1 = m.Vector2Add(center, m.Vector2Rotate(m.Vector2Subtract(l[1], center), state.lasers_rot));
        }

        var any_tail_hit = false;
        for (state.tail_pos) |p| {
            if (lineCircleIntersection(l0, l1, p, player_radius) != null) {
                any_tail_hit = true;
                break;
            }
        }

        if (any_tail_hit or
            c.CheckCollisionLines(l0, l1, state.tail_pos[0], state.tail_old_pos[0], null))
        {
            zap();
        }
        const x = time * 5;
        const y = @sin(4 * x) + @sin(0.3 + x) + @sin(1 - 0.4 * x);
        c.DrawLineEx(l0, l1, 3 + y * 0.1, c.Color{ .r = 150 + @floatToInt(u8, @fabs(@trunc(20 * y))), .g = 10, .b = 10, .a = 255 });
    }

    coroutines.resumeAll();

    c.EndMode2D();

    {
        // draw ui
        const color = if (state.planet_health > 70) c.GREEN else if (state.planet_health > 30) c.YELLOW else c.RED;
        if (prev_health != state.planet_health and frame_i % 16 < 4) {} else {
            c.DrawRing(center, 20, 24, 0, std.math.max(0, state.planet_health), 30, color);
        }
        c.DrawFPS(screenWidth - 80, 40);
        var buf: [64]u8 = undefined;
        drawText(std.fmt.bufPrintZ(&buf, "Tail left: {d}", .{tailLeft()}) catch "", m.Vector2{ .x = 140, .y = 40 });

        if (fade_to_white > 0) {
            c.DrawRectangle(0, 0, screenWidth, screenHeight, c.Fade(c.WHITE, fade_to_white));
        }

        ui_tasks.resumeAll();
    }

    const mouse_pos = m.Vector2{ .x = @intToFloat(f32, c.GetMouseX()), .y = @intToFloat(f32, c.GetMouseY())};
    if (gameplay_state == .alive) {
        c.DrawLineV(
            m.Vector2Add(mouse_pos, .{ .x = 0, .y = -5 }),
            m.Vector2Add(mouse_pos, .{ .x = 0, .y = 5 }),
            c.Color{ .r = 255, .g = 255, .b = 255, .a = 240 },
        );
        c.DrawLineV(
            m.Vector2Add(mouse_pos, .{ .x = -5, .y = 0 }),
            m.Vector2Add(mouse_pos, .{ .x = 5, .y = 0 }),
            c.Color{ .r = 255, .g = 255, .b = 255, .a = 240 },
        );
    } else {
        c.DrawCircleV(mouse_pos, 2, c.Color{ .r = 255, .g = 255, .b = 255, .a = 40 });
    }

    frame_i += 1;
}
