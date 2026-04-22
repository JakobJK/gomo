#pragma once

#include <godot_cpp/variant/vector3.hpp>
#include <array>
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
};

struct Face {
    static constexpr int HF_SIZE = 64;
    int32_t half_edge = -1;
    std::array<float, HF_SIZE * HF_SIZE * 2> tilt = {};
};

struct FaceFrame {
    godot::Vector3 origin, tangent, bitangent;
    float width  = 0.0f;
    float height = 0.0f;
};

} // namespace gomo
