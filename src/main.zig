// zig fmt: off

const std = @import("std");
const m = @import("math.zig");
const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    });

const print = std.debug.print;
const assert = std.debug.assert;
const eql = std.meta.eql;

// x = right, y = forward, z = up

const builtin = @import("builtin");
const developer_build: bool = true and builtin.mode != .ReleaseFast;

pub fn main() anyerror!void {

    //
    //      initialization
    //
    
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    cube_arraylist = std.ArrayList(rl.Vector3).init(allocator);
    defer cube_arraylist.deinit();

    rl.SetConfigFlags(rl.FLAG_MSAA_4X_HINT); // this has to go before InitWindow?

    rl.InitWindow(0, 0, "dungeon game"); // can't GetCurrentMonitor before InitWindow
    defer rl.CloseWindow(); // close window and OpenGL context
    const monitor: i32 = rl.GetCurrentMonitor();
    const screen_width: i32 = rl.GetMonitorWidth(monitor);
    const screen_height: i32 = rl.GetMonitorHeight(monitor);

    // this stuff has to go before something. i don't know exactly what. SetWindowSize?
    rl.SetConfigFlags(rl.FLAG_VSYNC_HINT);
    if (!developer_build) rl.SetTargetFPS(rl.GetMonitorRefreshRate(monitor))
    else rl.SetTargetFPS(rl.GetMonitorRefreshRate(monitor) * 2);
    //else rl.SetTargetFPS(30);
    
    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);

    if (developer_build) {
        const screen_width_f: f32 = @as(f32, @floatFromInt(screen_width));
        const screen_height_f: f32 = @as(f32, @floatFromInt(screen_height));
        rl.SetWindowSize(@intFromFloat(screen_width_f * 0.8), @intFromFloat(screen_height_f * 0.8));
        rl.SetWindowPosition(@intFromFloat(screen_width_f * 0.2), 39);
        }
    else {
        rl.SetWindowSize(screen_width, screen_height);
        rl.ToggleFullscreen();
        }
    rl.DisableCursor(); // limit cursor to relative movement inside the window


    //const player_collision_radius: f32 = 0.3;
    const player_height: f32 = 1.6764; // 5'6" lol
    var player_base: rl.Vector3 = .{.x = 3, .y = 0, .z = 0.001}; // change this!
    var camera = rl.Camera3D{
        .position   = m.sum(player_base, vec(0, 0, player_height - 0.25)), // do not change this. change player_base instead
        .target     = m.sum(player_base, vec(0, 1, player_height - 0.25)),
        .up         = vec(0, 0, 1),
        .fovy       = (@as(f32, 100) / @as(f32, @floatFromInt(screen_width))) * @as(f32, @floatFromInt(screen_height)),
        .projection = rl.CAMERA_PERSPECTIVE,
        };

    // pbr stuff
    // ==========================================================================
    // Load PBR shader and setup all required locations
    var shader: rl.Shader = rl.LoadShader("resources/pbr.vs", "resources/pbr.fs"); // GLSL version 330 because we don't care about android or web
    shader.locs[rl.SHADER_LOC_MAP_ALBEDO] = rl.GetShaderLocation(shader, "albedoMap");
    // WARNING: Metalness, roughness, and ambient occlusion are all packed into a MRA texture
    // They are passed as to the SHADER_LOC_MAP_METALNESS location for convenience,
    // shader already takes care of it accordingly
    shader.locs[rl.SHADER_LOC_MAP_METALNESS] =  rl.GetShaderLocation(shader, "mraMap");
    shader.locs[rl.SHADER_LOC_MAP_NORMAL] =    rl.GetShaderLocation(shader, "normalMap");
    // WARNING: Similar to the MRA map, the emissive map packs different information 
    // into a single texture: it stores height and emission data
    // It is binded to SHADER_LOC_MAP_EMISSION location an properly processed on shader
    shader.locs[rl.SHADER_LOC_MAP_EMISSION] =  rl.GetShaderLocation(shader, "emissiveMap");
    shader.locs[rl.SHADER_LOC_COLOR_DIFFUSE] = rl.GetShaderLocation(shader, "albedoColor");

    // Setup additional required shader locations, including lights data
    shader.locs[rl.SHADER_LOC_VECTOR_VIEW] = rl.GetShaderLocation(shader, "viewPos");
    const light_count_loc: i32 = rl.GetShaderLocation(shader, "numOfLights");
    const max_light_count: i32 = max_lights;
    rl.SetShaderValue(shader, light_count_loc, &max_light_count, rl.SHADER_UNIFORM_INT);

    // Setup ambient color and intensity parameters
    const ambient_intensity: f32 = 0.02;
    const ambient_color: rl.Color = col( 26, 32, 135, 255 );
    const ambient_color_normalized: rl.Vector3 = vec( 
        @as(f32, @floatFromInt(ambient_color.r)) / @as(f32, 255), 
        @as(f32, @floatFromInt(ambient_color.g)) / @as(f32, 255), 
        @as(f32, @floatFromInt(ambient_color.b)) / @as(f32, 255),
        );
    rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "ambientColor"), &ambient_color_normalized, rl.SHADER_UNIFORM_VEC3);
    rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "ambient"), &ambient_intensity, rl.SHADER_UNIFORM_FLOAT);

    // Get location for shader parameters that can be modified in real time
    const emissive_intensity_loc: i32 = rl.GetShaderLocation(shader, "emissivePower");
    const emissive_color_loc: i32 = rl.GetShaderLocation(shader, "emissiveColor");
    const texture_tiling_loc: i32 = rl.GetShaderLocation(shader, "tiling");

    // Load old car model using PBR maps and shader
    // WARNING: We know this model consists of a single model.meshes[0] and
    // that model.materials[0] is by default assigned to that mesh
    // There could be more complex models consisting of multiple meshes and
    // multiple materials defined for those meshes... but always 1 mesh = 1 material
    var car: rl.Model = rl.LoadModel("resources/old_car_new.glb");

    // Assign already setup PBR shader to model.materials[0], used by models.meshes[0]
    car.materials[0].shader = shader;

    // Setup materials[0].maps default parameters
    car.materials[0].maps[rl.MATERIAL_MAP_ALBEDO].color = rl.WHITE;
    car.materials[0].maps[rl.MATERIAL_MAP_METALNESS].value = 0;
    car.materials[0].maps[rl.MATERIAL_MAP_ROUGHNESS].value = 0;
    car.materials[0].maps[rl.MATERIAL_MAP_OCCLUSION].value = 1;
    car.materials[0].maps[rl.MATERIAL_MAP_EMISSION].color = col( 255, 162, 0, 255 );

    // Setup materials[0].maps default textures
    car.materials[0].maps[rl.MATERIAL_MAP_ALBEDO].texture    = rl.LoadTexture("resources/old_car_d.png");
    car.materials[0].maps[rl.MATERIAL_MAP_METALNESS].texture = rl.LoadTexture("resources/old_car_mra.png");
    car.materials[0].maps[rl.MATERIAL_MAP_NORMAL].texture    = rl.LoadTexture("resources/old_car_n.png");
    car.materials[0].maps[rl.MATERIAL_MAP_EMISSION].texture  = rl.LoadTexture("resources/old_car_e.png");

    // Load floor model mesh and assign material parameters
    // NOTE: A basic plane shape can be generated instead of being loaded from a model file
    var floor: rl.Model = rl.LoadModel("resources/plane.glb");
    //Mesh floorMesh = GenMeshPlane(10, 10, 10, 10);
    //GenMeshTangents(&floorMesh);      // TODO: Review tangents generation
    //Model floor = LoadModelFromMesh(floorMesh);

    // Assign material shader for our floor model, same PBR shader 
    floor.materials[0].shader = shader;
    
    floor.materials[0].maps[rl.MATERIAL_MAP_ALBEDO].color    = rl.WHITE;
    floor.materials[0].maps[rl.MATERIAL_MAP_METALNESS].value = @as(f32, 0);
    floor.materials[0].maps[rl.MATERIAL_MAP_ROUGHNESS].value = @as(f32, 0);
    floor.materials[0].maps[rl.MATERIAL_MAP_OCCLUSION].value = @as(f32, 1);
    floor.materials[0].maps[rl.MATERIAL_MAP_EMISSION].color  = rl.BLACK;

    floor.materials[0].maps[rl.MATERIAL_MAP_ALBEDO].texture    = rl.LoadTexture("resources/road_a.png");
    floor.materials[0].maps[rl.MATERIAL_MAP_METALNESS].texture = rl.LoadTexture("resources/road_mra.png");
    floor.materials[0].maps[rl.MATERIAL_MAP_NORMAL].texture    = rl.LoadTexture("resources/road_n.png");

    // Models texture tiling parameter can be stored in the Material struct if required (CURRENTLY NOT USED)
    // NOTE: Material.params[4] are available for generic parameters storage (float)
    const car_texture_tiling  : rl.Vector2 = vec2( 0.5, 0.5 );
    const floor_texture_tiling: rl.Vector2 = vec2( 0.5, 0.5 );

    // Create some lights
    var lights: [max_lights]Light = .{
        CreateLight(@as(i32, @intFromEnum(LightType.point)), .{ .x = 1.5, .y = 2.75, .z = 1.2 }, .{ .x = 0, .y = 0, .z = 0 }, rl.YELLOW, 4.0, shader),
        CreateLight(@as(i32, @intFromEnum(LightType.point)), .{ .x = 1.5, .y = -2.5, .z = 1.2 },   .{ .x = 0, .y = 0, .z = 0 }, rl.GREEN, 3.3, shader),
        CreateLight(@as(i32, @intFromEnum(LightType.point)), .{ .x = -1.5, .y = -2.5, .z = 1.2 },  .{ .x = 0, .y = 0, .z = 0 }, rl.RED, 8.3, shader),
        CreateLight(@as(i32, @intFromEnum(LightType.point)), .{ .x = -1.5, .y = 2.75, .z = 1.2 },  .{ .x = 0, .y = 0, .z = 0 }, rl.BLUE, 2.0, shader),
        };

    // Setup material texture maps usage in shader
    // NOTE: By default, the texture maps are always used
    var usage: i32 = 1;
    rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "useTexAlbedo"),   &usage, rl.SHADER_UNIFORM_INT);
    rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "useTexNormal"),   &usage, rl.SHADER_UNIFORM_INT);
    rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "useTexMRA"),      &usage, rl.SHADER_UNIFORM_INT);
    rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "useTexEmissive"), &usage, rl.SHADER_UNIFORM_INT);
    
    // my pbr stuf
    car.transform = rl.MatrixRotate(vec(1,0,0), std.math.rad_per_deg * 90);
    floor.transform = rl.MatrixRotate(vec(1,0,0), std.math.rad_per_deg * 90);
    // ==========================================================================

    // for level editing
    const cube_placement_max_distance: u8 = 64;
    var cube_placement_distance: f32 = 16;
    assert(cube_placement_distance <= cube_placement_max_distance);

    //
    //      main game loop
    //
    while (!rl.WindowShouldClose()) { // detect window close button or escape key
        const delta_time: f32 = rl.GetFrameTime();
        if (developer_build) {
            //if (delta_time > @as(f32, 1) / 96) print(terminal_error ++ "we had a frame that was longer than 1/96 of a second. it was {d:.4} seconds.\n" ++ terminal_default, .{delta_time});
            // nocheckin, uncomment this ^
            // my target is 1/96 (24 * 2^2) second frames on 80% of likely hardware, which is the equivalent of a 1060
            }

        // ================================================================
        //                  Update
        // ================================================================

        //
        //      get input
        //

        // TODO: when holding two conflicting inputs, make the new one supercede the old one,
        // so that we still move when we're holding both left and right
        const forward_input     : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_E))));
        const backward_input    : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_D))));
        const right_input       : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_F))));
        const left_input        : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_S))));

        const dolly_input       : f32 = forward_input - backward_input;
        const truck_input       : f32 = right_input - left_input;
        //const jump_input = rl.isKeyDown(.space);

        const up_arrow_input    : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_UP))));
        const down_arrow_input  : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_DOWN))));
        const right_arrow_input : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_RIGHT))));
        const left_arrow_input  : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_LEFT))));

        const sprint_input      : f32 = @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(rl.KEY_A))));

        const mouse_delta: rl.Vector2 = rl.Vector2Add(
            rl.Vector2Negate(rl.GetMouseDelta()), 
            .{
                .x = (left_arrow_input - right_arrow_input) * delta_time * 1200, 
                .y = (up_arrow_input - down_arrow_input) * delta_time * 900,
                },
            );

        // level editor inputs
        const primary_input     : bool = rl.IsMouseButtonPressed(rl.MOUSE_LEFT_BUTTON) or rl.IsKeyPressed(rl.KEY_SPACE);
        const secondary_input   : bool = rl.IsMouseButtonPressed(rl.MOUSE_RIGHT_BUTTON) or rl.IsKeyPressed(rl.KEY_G);
        const scroll_input: f32 = rl.GetMouseWheelMove();

        // pbr stuff
        // =========================================================================
        const camera_pos: [3]f32 = .{camera.position.x, camera.position.y, camera.position.z};
        rl.SetShaderValue(shader, shader.locs[rl.SHADER_LOC_VECTOR_VIEW], &camera_pos, rl.SHADER_UNIFORM_VEC3);

        // Check key inputs to enable/disable lights
        if (rl.IsKeyPressed(rl.KEY_ONE))   lights[2].enabled = @rem(lights[2].enabled + 1, 2);
        if (rl.IsKeyPressed(rl.KEY_TWO))   lights[1].enabled = @rem(lights[1].enabled + 1, 2);
        if (rl.IsKeyPressed(rl.KEY_THREE)) lights[3].enabled = @rem(lights[3].enabled + 1, 2);
        if (rl.IsKeyPressed(rl.KEY_FOUR))  lights[0].enabled = @rem(lights[0].enabled + 1, 2);

        // Update light values on shader (actually, only enable/disable them)
        for (lights) |light| UpdateLight(shader, light);
        // =========================================================================

        const move_speed: f32 = 3 + 4.5 * sprint_input;
        const mouse_sensitivity: f32 = 0.003;

        //
        //      pan and tilt camera
        //
        {
            const view_vector   : rl.Vector3 = rl.Vector3Normalize(m.difference(camera.target, camera.position));
            const forward_vector: rl.Vector3 = init: { // alternatively, we could project the view vector onto the plane of the floor.
                var vector = view_vector;
                vector.z = 0;
                vector = rl.Vector3Normalize(vector);
                break :init vector;
                };
            const right_vector  : rl.Vector3 = rl.Vector3RotateByAxisAngle(forward_vector, camera.up, -90 * std.math.rad_per_deg);
            

            const pitch_difference: f32 = init: {
                const angle = mouse_delta.y * mouse_sensitivity; // radians
                if (angle > 0 ) {
                    const max_difference: f32 = rl.Vector3Angle(camera.up, view_vector) - 0.001; // - 0.001 to "avoid numerical errors"
                    break :init @min(angle, max_difference);
                    }
                else {
                    const min_difference: f32 = -rl.Vector3Angle(rl.Vector3Negate(camera.up), view_vector) + 0.001;
                    break :init @max(angle, min_difference);
                    }
                };

            camera.target = 
                m.sum(
                    camera.position, 
                    m.sum(
                        rl.Vector3RotateByAxisAngle(view_vector, camera.up,    mouse_delta.x * mouse_sensitivity), // in radians
                        rl.Vector3RotateByAxisAngle(view_vector, right_vector, pitch_difference)  // in radians
                        )
                    );
            }

        const forward_vector: rl.Vector3 = init: { // alternatively, we could project the view vector onto the plane of the floor.
            var vector = rl.Vector3Normalize(m.difference(camera.target, player_base)); // view vector
            vector.z = 0;
            vector = rl.Vector3Normalize(vector);
            break :init vector;
            };
        const right_vector  : rl.Vector3 = rl.Vector3RotateByAxisAngle(forward_vector, camera.up, -90 * std.math.rad_per_deg);

        // =====================================================
        //              movement and collision
        // =====================================================

        //     we should probably have our collision system decide final move_offset based on initial move_offset,
        // not just potential location. this can probably solve the question of "when overlapping a ledge, should 
        // we move up or away?".

        //
        //      decide offset
        //
        const move_direction = rl.Vector3Normalize(m.sum(
            rl.Vector3Scale(forward_vector, dolly_input), 
            rl.Vector3Scale(right_vector, truck_input),
            ));
        const move_velocity = rl.Vector3Scale(move_direction, move_speed);
        const gravity = @as(rl.Vector3, .{ .x = 0, .y = 0, .z = -0.0 });
        const sum_velocity = m.sum(move_velocity, gravity);
        const move_offset: rl.Vector3 = rl.Vector3Scale(sum_velocity, delta_time);

        //const player_z_min = player_base.z;
        //const player_z_max = player_base.z + player_height;

        //collision_loop: while (true) {
        //    const potential_player_base = m.sum(player_base, move_offset);
        //    var shortest_distance: f32 = 0.001;
        //    var shortest_vector: rl.Vector3 = if (developer_build) vec(0,0,0) else undefined; // from triangle to player collsion
        //    var shortest_normal: rl.Vector3 = undefined;
        //    var collision_case: []const u8 = ""; // nocheckin, for debugging

        //    for (mesh_vertexes, mesh_vertex_indexes) |vertexes, vertex_indexes| {

        //        // TODO: optimization, add SAT-ish check to easily tell if we're not colliding with an object

        //        // TODO?: make an array of the z axes, and probably also the x and y axes
        //        blk: { // continue if vertexes are all above or all below the player
        //            assert(vertexes.len > 1);
        //            const first_z = vertexes[0].z;

        //            if (first_z < player_z_min) {
        //                for (vertexes[1..]) |vertex| {
        //                    if (vertex.z >= player_z_min) break :blk;
        //                    }
        //                //continue :meshes_loop;
        //                }
        //            
        //            else if (first_z > player_z_max) {
        //                for (vertexes[1..]) |vertex| {
        //                    if (vertex.z <= player_z_max) break :blk;
        //                    }
        //                //continue :meshes_loop;
        //                }
        //            }

        //        //_ = vertex_indexes;
        //        triangle_loop: for (vertex_indexes) |triangle| {
        //            const v1 = vertexes[triangle.a];
        //            const v2 = vertexes[triangle.b];
        //            const v3 = vertexes[triangle.c];
        //            const triangle_normal = rl.Vector3Normalize(m.crossProduct(m.difference(v2, v1), m.difference(v3, v1))); // also need this <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        //            const player_base_relative_to_v1: rl.Vector3 = m.difference(potential_player_base, v1);
        //            //const player_top_relative_to_v1: rl.Vector3 = vec(
        //            //    player_base_relative_to_v1.x, 
        //            //    player_base_relative_to_v1.y, 
        //            //    player_base_relative_to_v1.z + player_height,
        //            //    );
        //            
        //            // THIS IS NOT WHAT WE CURRENTLY DO:
        //            // for edges: 
        //            //     1. make sure that the edge runs through the z range
        //            //     2. see which side of the edge the cylinder is on
        //            //     if the cylinder is on both sides, then project both ends of the "cylinder" onto the plane's normal to see which is closer.
        //            //         if the "inner" one is closer, then the edge is not closer to the cylinder. the plane might be closer, or another edge might be closer. ...no?
        //            //     3. what do we do if the edge is closer? cross product? remember that cross product only works within the z range.
        //            //        alternatively, we could project the base or top of the cylinder onto the edge, since we know ... wait, this would only work on 
        //            //        edges that are partially out of the z range. it would not work on edges that are completely within the z range.
        //            // :THIS IS NOT WHAT WE CURRENTLY DO

        //            // optimization: make this branching more optimal. also, consider branchless

        //            const v1_to_v2 = m.difference(v2, v1);
        //            const v1_to_v3 = m.difference(v3, v1);

        //            //print("\n", .{});
        //            //
        //            //  edge 1
        //            //
        //            {
        //                const v_to_v_normal = rl.Vector3Normalize(v1_to_v2);
        //                const projection = rl.Vector3Scale(v_to_v_normal, m.dotProduct(v_to_v_normal, v1_to_v3));
        //                const edge_normal = rl.Vector3Normalize(m.difference(projection, v1_to_v3));
        //                const edge_is_closest_part = (m.dotProduct(edge_normal, player_base_relative_to_v1) > 0);
        //                if (edge_is_closest_part) {
        //                    const closest_point_on_edge = rl.Vector3Scale(v_to_v_normal, m.dotProduct(v_to_v_normal, player_base_relative_to_v1)); // closest point is relative
        //                    const xy_vector_to_edge = rl.Vector2{
        //                        .x = closest_point_on_edge.x - player_base_relative_to_v1.x,
        //                        .y = closest_point_on_edge.y - player_base_relative_to_v1.y,
        //                        };
        //                    const xy_distance_to_edge = rl.Vector2Length(xy_vector_to_edge) - player_collision_radius;
        //                    if (xy_distance_to_edge < shortest_distance) { // optimization: branchless
        //                        if (triangle_normal.z == 1) { // we're colliding with a flat floor
        //                            shortest_distance = player_base_relative_to_v1.z;
        //                            assert(eql(triangle_normal, vec(0,0,1)));
        //                            shortest_normal = triangle_normal;
        //                            shortest_vector = vec(0,0,shortest_distance);
        //                            collision_case = "edge 1, triangle_normal.z == 1";
        //                            }
        //                        else { // we're not colliding with a flat floor
        //                            shortest_distance = xy_distance_to_edge;
        //                            shortest_normal = vecFromVec2(rl.Vector2Normalize(rl.Vector2Negate(xy_vector_to_edge)));
        //                            shortest_vector = rl.Vector3Scale(shortest_normal, shortest_distance);
        //                            collision_case = "edge 1, triangle_normal.z != 1";
        //                            }
        //                        }
        //                    continue :triangle_loop;
        //                    }
        //                }

        //            //
        //            //  edge 3
        //            //
        //            {
        //                const v_to_v_normal = rl.Vector3Normalize(v1_to_v3);
        //                const projection = rl.Vector3Scale(v_to_v_normal, m.dotProduct(v_to_v_normal, v1_to_v2));
        //                const edge_normal = rl.Vector3Normalize(m.difference(projection, v1_to_v2));
        //                const edge_is_closest_part = (m.dotProduct(edge_normal, player_base_relative_to_v1) > 0);
        //                if (edge_is_closest_part) {
        //                    const closest_point_on_edge = rl.Vector3Scale(v_to_v_normal, m.dotProduct(v_to_v_normal, player_base_relative_to_v1)); // closest point is relative
        //                    const xy_vector_to_edge = rl.Vector2{
        //                        .x = closest_point_on_edge.x - player_base_relative_to_v1.x,
        //                        .y = closest_point_on_edge.y - player_base_relative_to_v1.y,
        //                        };
        //                    const xy_distance_to_edge = rl.Vector2Length(xy_vector_to_edge) - player_collision_radius;
        //                    if (xy_distance_to_edge < shortest_distance) { // optimization: branchless
        //                        if (triangle_normal.z == 1) { // we're colliding with a flat floor
        //                            shortest_distance = player_base_relative_to_v1.z;
        //                            print("distance: {}\n", .{shortest_distance});
        //                            assert(eql(triangle_normal, vec(0,0,1)));
        //                            shortest_normal = triangle_normal;
        //                            shortest_vector = vec(0,0,shortest_distance);
        //                            collision_case = "edge 3, triangle_normal.z == 1";
        //                            }
        //                        else { // we're not colliding with a flat floor
        //                            shortest_distance = xy_distance_to_edge;
        //                            shortest_normal = vecFromVec2(rl.Vector2Normalize(rl.Vector2Negate(xy_vector_to_edge)));
        //                            shortest_vector = rl.Vector3Scale(shortest_normal, shortest_distance);
        //                            collision_case = "edge 3, triangle_normal.z != 1";
        //                            }
        //                        }
        //                    continue :triangle_loop;
        //                    }
        //                }

        //            // these are needed only for edge 2
        //            const v2_to_v1 = rl.Vector3Negate(v1_to_v2); // optimization: we can probably get by without this
        //            const v2_to_v3 = m.difference(v3, v2);
        //            const player_base_relative_to_v2: rl.Vector3 = m.difference(potential_player_base, v2);

        //            //
        //            //  edge 2
        //            //
        //            {
        //                const v_to_v_normal = rl.Vector3Normalize(v2_to_v3);
        //                const projection = rl.Vector3Scale(v_to_v_normal, m.dotProduct(v_to_v_normal, v2_to_v1));
        //                const edge_normal = rl.Vector3Normalize(m.difference(projection, v2_to_v1));
        //                const edge_is_closest_part = (m.dotProduct(edge_normal, player_base_relative_to_v2) > 0); // relative to v1 won't work
        //                if (edge_is_closest_part) {
        //                    const closest_point_on_edge = rl.Vector3Scale(v_to_v_normal, m.dotProduct(v_to_v_normal, player_base_relative_to_v2)); // closest point is relative
        //                    const xy_vector_to_edge = rl.Vector2{
        //                        .x = closest_point_on_edge.x - player_base_relative_to_v2.x,
        //                        .y = closest_point_on_edge.y - player_base_relative_to_v2.y,
        //                        };
        //                    const xy_distance_to_edge = rl.Vector2Length(xy_vector_to_edge) - player_collision_radius;
        //                    if (xy_distance_to_edge < shortest_distance) { // optimization: branchless
        //                        if (triangle_normal.z == 1) { // we're colliding with a flat floor
        //                            shortest_distance = player_base_relative_to_v2.z;
        //                            print("distance: {}\n", .{shortest_distance});
        //                            assert(eql(triangle_normal, vec(0,0,1)));
        //                            shortest_normal = triangle_normal;
        //                            shortest_vector = vec(0,0,shortest_distance);
        //                            collision_case = "edge 2, triangle_normal.z == 1";
        //                            }
        //                        else { // we're not colliding with a flat floor
        //                            shortest_distance = xy_distance_to_edge;
        //                            shortest_normal = vecFromVec2(rl.Vector2Normalize(rl.Vector2Negate(xy_vector_to_edge)));
        //                            shortest_vector = rl.Vector3Scale(shortest_normal, shortest_distance);
        //                            collision_case = "edge 2, triangle_normal.z != 1";
        //                            }
        //                        }
        //                    continue :triangle_loop;
        //                    }
        //                }

        //            //print("all false\n", .{});

        //            // plane
        //            const direction_to_cylinder_edge: rl.Vector2 = .{ .x = -triangle_normal.x, .y = -triangle_normal.y };
        //            const vector_to_cylinder_edge = rl.Vector2Scale(rl.Vector2Normalize(direction_to_cylinder_edge), player_collision_radius);

        //            //const normal_z: u8 = @intFromBool(triangle_normal.z < 0); // branchless programming!
        //            assert(!(triangle_normal.z < 0)); // i expect we'll never have to worry about hitting our heads.
        //            const normal_z: u8 = 0;

        //            const relative_near_point: rl.Vector3 = .{ 
        //                .x = player_base_relative_to_v1.x + vector_to_cylinder_edge.x, 
        //                .y = player_base_relative_to_v1.y + vector_to_cylinder_edge.y, 
        //                .z = player_base_relative_to_v1.z + player_height * @as(f32, @floatFromInt(normal_z)),
        //                };
        //            const raw_distance_to_near_point = m.dotProduct(relative_near_point, triangle_normal); // not absolute, so it can return negative values, which is not what we want to use for checking distance to a plane.
        //            const vector_to_near_point = rl.Vector3Scale(triangle_normal, raw_distance_to_near_point); // vector from plane to nearest point on cylinder // here! <<<<<<<<<<<<<<<<<<<
        //            const xy_intersection = rl.Vector2Length(@as(rl.Vector2, rl.Vector2{.x = vector_to_near_point.x, .y = vector_to_near_point.y}));
        //            if (raw_distance_to_near_point < shortest_distance and @abs(vector_to_near_point.z) < player_height and xy_intersection < player_collision_radius * 2) {
        //                shortest_distance = raw_distance_to_near_point;
        //                shortest_vector = vector_to_near_point;
        //                shortest_normal = triangle_normal;
        //                collision_case = "plane";
        //                }

        //            }
        //        }

        //    print("collision case: {s}\n", .{collision_case});

        //    if (shortest_distance < 0) {
        //        move_offset = m.difference(move_offset, m.difference(shortest_vector, rl.Vector3Scale(shortest_normal, 0.001)));
        //        continue :collision_loop;
        //        }

        //    break;
        //    }

        player_base     = m.sum(player_base, move_offset);
        camera.position = m.sum(camera.position, move_offset);
        camera.target   = m.sum(camera.target, move_offset);

        //
        //      actions
        //
        const view_vector: rl.Vector3 = rl.Vector3Normalize(m.difference(camera.target, camera.position));

        //
        //      level editing
        //

        // next: 
        // saving data to disk
        // more features:
        //     ramps
        //     rows
        //     planes

        cube_placement_distance = std.math.clamp(scroll_input + cube_placement_distance, 1, @as(f32, @floatFromInt(cube_placement_max_distance)));
        // conceive potential cube placement locations
        var potential_placements_buffer: [cube_placement_max_distance]rl.Vector3 = undefined; // change the length of this array to increase the max place distance
        const potential_placements: []rl.Vector3 = potential_placements_buffer[0..@as(usize, @intFromFloat(@ceil(cube_placement_distance)))];
        for (potential_placements, 0..) |*e, i| {
            const raw_location = m.sum(camera.position, rl.Vector3Scale(view_vector, @as(f32, @floatFromInt(i + 1))));
            e.* = .{
                .x = @round(raw_location.x),
                .y = @round(raw_location.y),
                .z = @round(raw_location.z),
                };
            }

        if (primary_input) {
            // find furthest valid placement and put a block there
            var furthest_valid_index: ?u8 = null;
            placement_loop: for (potential_placements, 0..) |placement, index| {
                for (cube_arraylist.items) |cube| {
                    if (eql(cube, placement)) {
                        if (index > 0) furthest_valid_index = @intCast(index - 1);
                        break :placement_loop;
                        }
                    }
                furthest_valid_index = @intCast(potential_placements.len - 1);
                }
            if (furthest_valid_index) |fvi| try cube_arraylist.append(potential_placements[fvi]);
            }

        if (secondary_input) {
            // find nearest invalid placement and remove the block there
            deletion_loop: for (potential_placements) |deletion_location| {
                for (cube_arraylist.items, 0..) |cube, cube_index| {
                    if (eql(cube, deletion_location)) {
                        _ = cube_arraylist.swapRemove(cube_index);
                        break :deletion_loop;
                        }
                    }
                }
            }

        // =======================================================
        //                          draw
        // =======================================================
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        {
            rl.BeginMode3D(camera);
            defer rl.EndMode3D();

            for (lines_to_draw) |e| {
                rl.DrawLine3D(e.start, e.end, e.color);
                }

            for (mesh_vertexes, mesh_vertex_indexes) |vertexes, vertex_indexes| {
                for (vertex_indexes) |index_struct| {
                    rl.DrawTriangle3D(vertexes[index_struct.a], vertexes[index_struct.b], vertexes[index_struct.c], beige);
                    rl.DrawLine3D(vertexes[index_struct.a], vertexes[index_struct.b], cyan);
                    rl.DrawLine3D(vertexes[index_struct.b], vertexes[index_struct.c], cyan);
                    rl.DrawLine3D(vertexes[index_struct.c], vertexes[index_struct.a], cyan);
                    }
                }

            // voxel level
            for (cube_arraylist.items) |cube_location| {
                rl.DrawCube(cube_location, 1, 1, 1, beige);
                }
            // draw where cube would be placed
            // find furthest valid placement and draw a wire cube there
            {
                var furthest_valid_index: ?u8 = null;
                placement_loop: for (potential_placements, 0..) |placement, index| {
                    for (cube_arraylist.items) |cube| {
                        if (eql(cube, placement)) {
                            if (index > 0) furthest_valid_index = @intCast(index - 1);
                            break :placement_loop;
                            }
                        }
                    furthest_valid_index = @intCast(potential_placements.len - 1);
                    }
                if (furthest_valid_index) |fvi| rl.DrawCubeWires(potential_placements[fvi], 1, 1, 1, green);
                }
            // draw what cube would be deleted
            // find nearest invalid placement and draw cube there
            deletion_loop: for (potential_placements) |deletion_location| {
                for (cube_arraylist.items) |cube| {
                    if (eql(cube, deletion_location)) {
                        rl.DrawCubeWires(cube, 1, 1, 1, red);
                        break :deletion_loop;
                        }
                    }
                }

            // pbr stuff
            // ==================================================================================================================
            // Set floor model texture tiling and emissive color parameters on shader
            rl.SetShaderValue(shader, texture_tiling_loc, &floor_texture_tiling, rl.SHADER_UNIFORM_VEC2);
            const floor_emissive_color: rl.Vector4 = rl.ColorNormalize(floor.materials[0].maps[rl.MATERIAL_MAP_EMISSION].color);
            rl.SetShaderValue(shader, emissive_color_loc, &floor_emissive_color, rl.SHADER_UNIFORM_VEC4);
            
            rl.DrawModel(floor, vec( 0, 0, 0.005 ), @as(f32, 5), rl.WHITE);   // Draw floor model

            // Set old car model texture tiling, emissive color and emissive intensity parameters on shader
            rl.SetShaderValue(shader, texture_tiling_loc, &car_texture_tiling, rl.SHADER_UNIFORM_VEC2);
            const car_emissive_color: rl.Vector4 = rl.ColorNormalize(car.materials[0].maps[rl.MATERIAL_MAP_EMISSION].color);
            rl.SetShaderValue(shader, emissive_color_loc, &car_emissive_color, rl.SHADER_UNIFORM_VEC4);
            const emissive_intensity: f32 = 0.01;
            rl.SetShaderValue(shader, emissive_intensity_loc, &emissive_intensity, rl.SHADER_UNIFORM_FLOAT);
            
            rl.DrawModel(car, vec( 0, 0, 0 ), 0.3, rl.WHITE);   // Draw car model

            // Draw spheres to show the lights positions
            for (lights) |light| {
                const light_color: rl.Color = col( 
                    @as(u8, @intFromFloat(light.color[0] * 255)), 
                    @as(u8, @intFromFloat(light.color[1] * 255)), 
                    @as(u8, @intFromFloat(light.color[2] * 255)), 
                    @as(u8, @intFromFloat(light.color[3] * 255)),
                    );
                
                if (light.enabled == 1) rl.DrawSphereEx(light.position, 0.2, 8, 8, light_color)
                else rl.DrawSphereWires(light.position, 0.2, 8, 8, rl.ColorAlpha(light_color, 0.3));
                }
            // ==================================================================================================================
            }

        rl.DrawText("Toggle lights: [1][2][3][4]", 10, 40, 20, rl.LIGHTGRAY);

        rl.DrawFPS(10, 10);

        }
    }

// some convenient colors
const black       : rl.Color = .{ .r =   0, .g =   0, .b =   0, .a = 255 };
const red         : rl.Color = .{ .r = 255, .g =   0, .b =   0, .a = 255 };
const yellow      : rl.Color = .{ .r = 255, .g = 255, .b =   0, .a = 255 };
const green       : rl.Color = .{ .r =   0, .g = 255, .b =   0, .a = 255 };
const cyan        : rl.Color = .{ .r =   0, .g = 255, .b = 255, .a = 255 };
const blue        : rl.Color = .{ .r =   0, .g =   0, .b = 255, .a = 255 };
const magenta     : rl.Color = .{ .r = 255, .g =   0, .b = 255, .a = 255 };
const white       : rl.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
const yellow_gold : rl.Color = .{ .r = 252, .g = 188, .b =   4, .a = 255 };
const beige       : rl.Color = .{ .r = 220, .g = 200, .b = 180, .a = 255 };

var lines_to_draw = init: {
    const line_capacity: comptime_int = 1024 * 16;
    @setEvalBranchQuota(line_capacity);
    var array: [line_capacity]struct{ start: rl.Vector3, end: rl.Vector3, color: rl.Color } = undefined;
    for (&array) |*i| {
        i.* = .{ 
            .start = .{ .x = 0, .y = 0, .z = 0 }, 
            .end = .{ .x = 0, .y = 0, .z = 0 }, 
            .color = .{ .r = 0, .b = 0, .g = 0, .a = 0 },
            };
        }
    break :init array;
    };

var lines_to_draw_cursor: usize = 0;

fn scheduleLineDraw(start: rl.Vector3, end: rl.Vector3, color: rl.Color) void {
    lines_to_draw[lines_to_draw_cursor] = .{ .start = start, .end = end, .color = color };
    lines_to_draw_cursor += 1;
    if (lines_to_draw_cursor == lines_to_draw.len) lines_to_draw_cursor = 0;
    }

// TODO: put all vertexes into one array at comptime, and know which are associated using lengths. and have an array for each axis, or at least the z?
const mesh_vertexes = [_][]const rl.Vector3{
    //single_triangle.vertexes,
    box.vertexes,
    wall.vertexes,
    floor_collision.vertexes,
    };
const mesh_vertex_indexes = [_][]const TriangleVertexIndexes{
    //single_triangle.vertex_indexes,
    box.vertex_indexes,
    wall.vertex_indexes,
    floor_collision.vertex_indexes,
    };

const Mesh = struct{
    vertexes: []const rl.Vector3,
    vertex_indexes: []const TriangleVertexIndexes,
    };
const TriangleVertexIndexes = struct{ a: u8, b: u8, c: u8};  // raylib expects counter-clock-wise

const single_triangle: Mesh = .{
    .vertexes = &.{
        vec(4,1,0.6),
        vec(4,1,2),
        vec(4,4,0.6),
        },
    .vertex_indexes = &.{
        .{ .a = 0, .b = 1, .c = 2 },
        },
    };

const wall: Mesh = .{
    .vertexes = &.{
        vec(3,-1,0),
        vec(3,-1,2),
        vec(6,-1,0),
        vec(3,-1.05,0),
        vec(3,-1.05,2),
        vec(6,-1.05,0),
        },
    .vertex_indexes = &.{
        .{ .a = 0, .b = 1, .c = 2 },
        .{ .a = 5, .b = 4, .c = 3 },
        },
    };

const box: Mesh = .{
    .vertexes = &.{
        vec(4,2,0),
        vec(4,2,2),
        vec(4,3,0),
        vec(4,3,2),
        vec(5,2,0),
        vec(5,3,0),
        },
    .vertex_indexes = &.{
        .{ .a = 0, .b = 1, .c = 2 },
        .{ .a = 3, .b = 2, .c = 1 },
        .{ .a = 1, .b = 0, .c = 4 },
        .{ .a = 1, .b = 4, .c = 5 },
        .{ .a = 3, .b = 1, .c = 5 },
        .{ .a = 3, .b = 5, .c = 2 },
        },
    };

const floor_collision: Mesh = .{
    .vertexes = &.{
        vec( 10,  10, 0), // 0.001 to not z-fight with pretty floor
        vec(-10, -10, 0),
        vec( 10, -10, 0),
        vec(-10,  10, 0),
        },
    .vertex_indexes = &.{
        .{ .a = 0, .b = 1, .c = 2 },
        .{ .a = 0, .b = 3, .c = 1 },
        },
    };

const csi = [2]u8{ 27, '[' }; //same as: "\x1B[";
const terminal_error = csi ++ "38;5;196m"; // red
const terminal_default = csi ++ "0m"; // back to default

    
fn vec(x: f32, y: f32, z: f32) rl.Vector3 {
    return .{ .x = x, .y = y, .z = z };
    }

fn vec2(x: f32, y: f32) rl.Vector2 {
    return .{ .x = x, .y = y };
    }

fn vecFromVec2(v: rl.Vector2) rl.Vector3 {
    return .{ .x = v.x, .y = v.y, .z = 0 };
    }

fn col(r: u8, g: u8, b: u8, a: u8) rl.Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
    }


const max_lights = 4;

const LightType = enum{ directional, point, spot };

// Light data
const Light = struct {
    typ      : i32,
    enabled  : i32,
    position : rl.Vector3,
    target   : rl.Vector3,
    color    : [4]f32,
    intensity: f32,

    // Shader light parameters locations
    typ_loc      : i32,
    enabled_loc  : i32,
    position_loc : i32,
    target_loc   : i32,
    color_loc    : i32,
    intensity_loc: i32,
    };

//----------------------------------------------------------------------------------
// Global Variables Definition
//----------------------------------------------------------------------------------
var light_count: i32 = 0;     // Current number of dynamic lights that have been created

// Create light with provided data
// NOTE: It updated the global lightCount and it's limited to MAX_LIGHTS
fn CreateLight(typ: i32, position: rl.Vector3, target: rl.Vector3, color: rl.Color, intensity: f32, shader: rl.Shader) Light {
    var light: Light = .{
        .enabled = 0,
        .typ = 0,
        .position = vec(0,0,0),
        .target = vec(0,0,0),
        .color = .{ 0, 0, 0, 0 },
        .intensity = 0,

        .enabled_loc = 0,
        .typ_loc = 0,
        .position_loc = 0,
        .target_loc = 0,
        .color_loc = 0,
        .intensity_loc = 0,
        };

    if (light_count < max_lights) {
        light.enabled = 1;
        light.typ = typ;
        light.position = position;
        light.target = target;
        light.color[0] = @as(f32, @floatFromInt(color.r)) / @as(f32, 255);
        light.color[1] = @as(f32, @floatFromInt(color.g)) / @as(f32, 255);
        light.color[2] = @as(f32, @floatFromInt(color.b)) / @as(f32, 255);
        light.color[3] = @as(f32, @floatFromInt(color.a)) / @as(f32, 255);
        light.intensity = intensity;
       
        switch (light_count) {
            0 => {
                // NOTE: Shader parameters names for lights must match the requested ones
                light.enabled_loc   = rl.GetShaderLocation(shader, "lights[0].enabled"); // futurebug: zig string vs C's null-terminated string
                light.typ_loc       = rl.GetShaderLocation(shader, "lights[0].type"); // futurebug: type vs typ
                light.position_loc  = rl.GetShaderLocation(shader, "lights[0].position");
                light.target_loc    = rl.GetShaderLocation(shader, "lights[0].target");
                light.color_loc     = rl.GetShaderLocation(shader, "lights[0].color");
                light.intensity_loc = rl.GetShaderLocation(shader, "lights[0].intensity");
            },
            1 => {
                // NOTE: Shader parameters names for lights must match the requested ones
                light.enabled_loc   = rl.GetShaderLocation(shader, "lights[1].enabled"); // futurebug: zig string vs C's null-terminated string
                light.typ_loc       = rl.GetShaderLocation(shader, "lights[1].type"); // futurebug: type vs typ
                light.position_loc  = rl.GetShaderLocation(shader, "lights[1].position");
                light.target_loc    = rl.GetShaderLocation(shader, "lights[1].target");
                light.color_loc     = rl.GetShaderLocation(shader, "lights[1].color");
                light.intensity_loc = rl.GetShaderLocation(shader, "lights[1].intensity");
            },
            2 => {
                // NOTE: Shader parameters names for lights must match the requested ones
                light.enabled_loc   = rl.GetShaderLocation(shader, "lights[2].enabled"); // futurebug: zig string vs C's null-terminated string
                light.typ_loc       = rl.GetShaderLocation(shader, "lights[2].type"); // futurebug: type vs typ
                light.position_loc  = rl.GetShaderLocation(shader, "lights[2].position");
                light.target_loc    = rl.GetShaderLocation(shader, "lights[2].target");
                light.color_loc     = rl.GetShaderLocation(shader, "lights[2].color");
                light.intensity_loc = rl.GetShaderLocation(shader, "lights[2].intensity");
            },
            3 => {
                // NOTE: Shader parameters names for lights must match the requested ones
                light.enabled_loc   = rl.GetShaderLocation(shader, "lights[3].enabled"); // futurebug: zig string vs C's null-terminated string
                light.typ_loc       = rl.GetShaderLocation(shader, "lights[3].type"); // futurebug: type vs typ
                light.position_loc  = rl.GetShaderLocation(shader, "lights[3].position");
                light.target_loc    = rl.GetShaderLocation(shader, "lights[3].target");
                light.color_loc     = rl.GetShaderLocation(shader, "lights[3].color");
                light.intensity_loc = rl.GetShaderLocation(shader, "lights[3].intensity");
            },
            4 => {
                // NOTE: Shader parameters names for lights must match the requested ones
                light.enabled_loc   = rl.GetShaderLocation(shader, "lights[4].enabled"); // futurebug: zig string vs C's null-terminated string
                light.typ_loc       = rl.GetShaderLocation(shader, "lights[4].type"); // futurebug: type vs typ
                light.position_loc  = rl.GetShaderLocation(shader, "lights[4].position");
                light.target_loc    = rl.GetShaderLocation(shader, "lights[4].target");
                light.color_loc     = rl.GetShaderLocation(shader, "lights[4].color");
                light.intensity_loc = rl.GetShaderLocation(shader, "lights[4].intensity");
            },
            else => unreachable,
        }
        
        UpdateLight(shader, light);

        light_count += 1;
        }

    return light;
    }
// Send light properties to shader
// NOTE: Light shader locations should be available
fn UpdateLight(shader: rl.Shader, light: Light) void { // these are supposed to be ?*const anyopaques?
    rl.SetShaderValue(shader, light.enabled_loc, &light.enabled, rl.SHADER_UNIFORM_INT);
    rl.SetShaderValue(shader, light.typ_loc, &light.typ, rl.SHADER_UNIFORM_INT);
    
    // Send to shader light position values
    const position: [3]f32 = .{ light.position.x, light.position.y, light.position.z };
    rl.SetShaderValue(shader, light.position_loc, &position, rl.SHADER_UNIFORM_VEC3);

    // Send to shader light target position values
    const target: [3]f32 = .{ light.target.x, light.target.y, light.target.z };
    rl.SetShaderValue(shader, light.target_loc, &target, rl.SHADER_UNIFORM_VEC3);
    rl.SetShaderValue(shader, light.color_loc, &light.color, rl.SHADER_UNIFORM_VEC4);
    rl.SetShaderValue(shader, light.intensity_loc, &light.intensity, rl.SHADER_UNIFORM_FLOAT);
}

var cube_arraylist: std.ArrayList(rl.Vector3) = undefined;
