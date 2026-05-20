#pragma once

#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <cstdint>

namespace gomo {

struct Vertex {
    godot::Vector3 position;
    int32_t half_edge = -1;
};

struct HalfEdge {
    int32_t vertex = -1;
    int32_t twin   = -1;
    int32_t next   = -1;
    int32_t prev   = -1;
    int32_t face   = -1;
    godot::Vector2 uv          = {};
    bool           seam        = false;
    bool           manual_seam = false;
    float          crease = 0.0f;
};

struct Face {
    int32_t half_edge = -1;
};

} // namespace gomo
