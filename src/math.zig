// zig fmt: off

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    });
const std = @import("std");
const main = @import("main.zig");

const print = std.debug.print;


pub fn sum(augend: rl.Vector3, addend: rl.Vector3) rl.Vector3 {
    return .{ 
        .x = augend.x + addend.x, 
        .y = augend.y + addend.y, 
        .z = augend.z + addend.z 
        };
    }

pub fn difference(minuend: rl.Vector3, subtrahend: rl.Vector3) rl.Vector3 {
    return .{ 
        .x = minuend.x - subtrahend.x, 
        .y = minuend.y - subtrahend.y, 
        .z = minuend.z - subtrahend.z 
        };
    }

pub fn dotProduct(a: rl.Vector3, b: rl.Vector3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
    }

pub fn crossProduct(a: rl.Vector3, b: rl.Vector3) rl.Vector3 { // provides vector perpendicular to both given vectors
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
        };
    }

// ==================================================
//              unused past here
// ==================================================

// could this be done better the other way?
pub fn projectVectorOntoPlane(vector: rl.Vector3, plane_normal: rl.Vector3) rl.Vector3 { // plane_normal is assumed to be normalized
    if (main.developer_build) {
        const magnitude = rl.Vector3Length(plane_normal);
        if (magnitude > 1.001 or magnitude < 0.999) print(main.terminal_error ++ "\nthis is supposed to be normalized, idiot!" ++ main.terminal_default, .{});
        }
    return difference(vector, rl.Vector3Scale(plane_normal, dotProduct(plane_normal, vector))); // same as finding the "velocity"/vector perpendicular to a direction
    }

// deprecated?
pub fn nearestPointOnLineSegment(absolute_point: rl.Vector3, segment_endpoint_a: rl.Vector3, segment_endpoint_b: rl.Vector3) rl.Vector3 {
    // note: the segment endpoints are interchangeable; it doesn’t matter which endpoint is a or b.
    
    //
    //      turn things relative
    //
    const relative_point = difference(absolute_point, segment_endpoint_a);
    const line = difference(segment_endpoint_b, segment_endpoint_a);

    //
    //      project the point onto the line
    //
    const ratio: f32 = dotProduct(relative_point, line) / dotProduct(line, line);

    const nearest_point: rl.Vector3 = 
        if (ratio > 1) // nearest point on the line segment is segment_endpoint_b
            line
        else if (ratio < 0) // nearest point on the line segment is segment_endpoint_a
            .{.x = 0, .y = 0, .z = 0}
        else // nearest point on the line segment is between segment_endpoint_a and segment_endpoint_b
            line.scale(ratio)
        ;
    
    //
    //      turn things back absolute
    //
    return sum(nearest_point, segment_endpoint_a);
    }

// could this be done better the other way? or a third way?
pub fn vectorFromPointToLine(point: rl.Vector3, line_point_a: rl.Vector3, line_point_b: rl.Vector3) rl.Vector3 {
    
    //
    //      turn things relative
    //
    const relative_point = difference(point, line_point_a);
    const line = difference(line_point_b, line_point_a);

    //
    //      project the point onto the line
    //
    const ratio: f32 = dotProduct(relative_point, line) / dotProduct(line, line);

    const nearest_point: rl.Vector3 = line.scale(ratio);
    return difference(nearest_point, relative_point);
    }

pub fn vectorFromNearestPointOnLineSegment(relative_point: rl.Vector3, line: rl.Vector3) rl.Vector3 {
    // note: both arguments are RELATIVE.
    //     line should be acquired by subtracting the end of the line segment in 
    // absolute space from the beginning of the line segment in absolute space.
    // relative_point should be acquired by subtracting the point in absolute space 
    // from the beginning of the line segment in absolute space. it doesn't matter 
    // whether you subtract the beginning or end of the line from each argument, but 
    // it has to be the same for both.
    
    // project the point onto the line
    const ratio: f32 = dotProduct(relative_point, line) / dotProduct(line, line);

    const nearest_point_on_line: rl.Vector3 = 
        if (ratio > 1) //                nearest point on the line is the end
            line //                          --- X
        else if (ratio < 0) //           nearest point on the line is the beginning
            .{.x = 0, .y = 0, .z = 0} //   X ---
        else //                          nearest point on the line segment is between the beginning and end
            line.scale(ratio) //             -X-
        ;

    // get vector from nearest_point_on_line to relative_point
    return difference(relative_point, nearest_point_on_line);
    }

pub fn vectorFromNearestPointOnTriangle(point: rl.Vector3, normal: rl.Vector3, v1: rl.Vector3, v2: rl.Vector3, v3: rl.Vector3) rl.Vector3 {

    const point_relative_to_v1 = difference(point, v1);

    // check to see if closest point is on the first edge of the triangle
    const edge_1 = difference(v2, v1);
    if (!behindPlane(point_relative_to_v1, crossProduct(edge_1, normal))) { // note: the order of cross product matters!
        return vectorFromNearestPointOnLineSegment(point_relative_to_v1, edge_1);
        }

    // check to see if closest point is on the second edge of the triangle
    const point_relative_to_v2 = difference(point, v2);
    const edge_2 = difference(v3, v2);
    if (!behindPlane(point_relative_to_v2, crossProduct(edge_2, normal))) {
        return vectorFromNearestPointOnLineSegment(point_relative_to_v2, edge_2);
        }

    // check to see if closest point is on the third edge of the triangle
    const edge_3 = difference(v3, v1);
    if (!behindPlane(point_relative_to_v1, crossProduct(normal, edge_3))) {
        return vectorFromNearestPointOnLineSegment(point_relative_to_v1, edge_3);
        }

    // find distance to triangle face
    return normal.scale(dotProduct(point_relative_to_v1, normal));
    }

pub fn behindPlane(relative_point: rl.Vector3, plane_normal: rl.Vector3) bool {
    // point is assumed to be RELATIVE to any point on the plane. ie. the plane intersects (0,0,0)
    // plane_normal doesn't have to be normalized
    if (dotProduct(relative_point, plane_normal) > 0) return false else return true; // intersecting the plane is considered "past" the plane
    }

