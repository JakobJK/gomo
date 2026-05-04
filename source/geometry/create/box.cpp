#include "box.h"

#include <unordered_map>
#include <vector>
#include <algorithm>

using namespace godot;

namespace gomo {

    namespace {

        struct EdgeKey {
            int32_t a, b;
            bool operator==(const EdgeKey &o) const { return a == o.a && b == o.b; }
        };

        struct EdgeKeyHash {
            size_t operator()(const EdgeKey &k) const {
                return std::hash<int64_t>()(((int64_t)k.a << 32) | (uint32_t)k.b);
            }
        };

        // 2D grid of vertex indices stored row-major. Unallocated slots hold -1.
        struct Grid {
            std::vector<int32_t> idx;
            int cols;
            Grid(int rows, int cols) : idx(rows * cols, -1), cols(cols) {}
            int32_t& operator()(int row, int col) { return idx[row * cols + col]; }
        };

    } // anonymous namespace

// Builds a subdivided box. Each face gets a pre-allocated vertex grid; boundary
// vertices are copied from already-built adjacent grids so every seam vertex is
// shared by a single index — no floating-point recomputation across faces.
//
// Outward CCW winding (normal = du x dv) per face:
//   bottom  -Y  u->X(-hw..+hw)   v->Z(-hd..+hd)
//   top     +Y  u->X(-hw..+hw)   v->Z(+hd..-hd)
//   front   -Z  u->X(+hw..-hw)   v->Y(-hh..+hh)
//   back    +Z  u->X(-hw..+hw)   v->Y(-hh..+hh)
//   left    -X  u->Z(-hd..+hd)   v->Y(-hh..+hh)
//   right   +X  u->Z(+hd..-hd)   v->Y(-hh..+hh)
void build_box(HalfEdgeMesh &mesh,
               float width, float height, float depth,
               int32_t width_segments, int32_t height_segments, int32_t depth_segments) {
    mesh.clear();

    const int32_t ws = std::max(1, (int)width_segments);
    const int32_t hs = std::max(1, (int)height_segments);
    const int32_t ds = std::max(1, (int)depth_segments);

    const float hw = width  * 0.5f;
    const float hh = height * 0.5f;
    const float hd = depth  * 0.5f;

    Grid bottom(ds+1, ws+1);
    Grid top   (ds+1, ws+1);
    Grid front (hs+1, ws+1);
    Grid back  (hs+1, ws+1);
    Grid left  (hs+1, ds+1);
    Grid right (hs+1, ds+1);

    auto alloc = [&](Vector3 p) -> int32_t {
        int32_t idx = (int32_t)mesh.vertices.size();
        mesh.vertices.push_back({p, -1});
        return idx;
    };

    // --- Allocate vertices ---

    for (int v = 0; v <= ds; ++v)
        for (int u = 0; u <= ws; ++u)
            bottom(v, u) = alloc({-hw + (float)u/ws * width,  -hh,  -hd + (float)v/ds * depth});

    for (int v = 0; v <= ds; ++v)
        for (int u = 0; u <= ws; ++u)
            top(v, u) = alloc({-hw + (float)u/ws * width,  +hh,  +hd - (float)v/ds * depth});

    // Front: x runs reversed, so its bottom/top edges mirror bottom/top's v=0 row
    for (int u = 0; u <= ws; ++u) {
        front(0,  u) = bottom(0,  ws - u);
        front(hs, u) = top   (ds, ws - u);
    }
    for (int v = 0; v <= hs; ++v)
        for (int u = 0; u <= ws; ++u)
            if (front(v, u) == -1)
                front(v, u) = alloc({+hw - (float)u/ws * width,  -hh + (float)v/hs * height,  -hd});

    // Back: x runs same direction, edges share directly
    for (int u = 0; u <= ws; ++u) {
        back(0,  u) = bottom(ds, u);
        back(hs, u) = top   (0,  u);
    }
    for (int v = 0; v <= hs; ++v)
        for (int u = 0; u <= ws; ++u)
            if (back(v, u) == -1)
                back(v, u) = alloc({-hw + (float)u/ws * width,  -hh + (float)v/hs * height,  +hd});

    // Left: all four edges are seams
    for (int u = 0; u <= ds; ++u) {
        left(0,  u) = bottom(u,      0);   // bottom col-0  (same z direction)
        left(hs, u) = top   (ds - u, 0);   // top    col-0  (z reversed)
    }
    for (int v = 0; v <= hs; ++v) {
        left(v,  0) = front(v, ws);        // front's rightmost col
        left(v, ds) = back (v, 0);         // back's  leftmost  col
    }
    for (int v = 0; v <= hs; ++v)
        for (int u = 0; u <= ds; ++u)
            if (left(v, u) == -1)
                left(v, u) = alloc({-hw,  -hh + (float)v/hs * height,  -hd + (float)u/ds * depth});

    // Right: all four edges are seams
    for (int u = 0; u <= ds; ++u) {
        right(0,  u) = bottom(ds - u, ws); // bottom col-ws (z reversed)
        right(hs, u) = top   (u,      ws); // top    col-ws (same z direction)
    }
    for (int v = 0; v <= hs; ++v) {
        right(v,  0) = back (v, ws);       // back's  rightmost col
        right(v, ds) = front(v, 0);        // front's leftmost  col
    }
    for (int v = 0; v <= hs; ++v)
        for (int u = 0; u <= ds; ++u)
            if (right(v, u) == -1)
                right(v, u) = alloc({+hw,  -hh + (float)v/hs * height,  +hd - (float)u/ds * depth});

    // --- Build quads and wire twins ---
    std::unordered_map<EdgeKey, int32_t, EdgeKeyHash> edge_map;

    auto build_quads = [&](Grid &grid, int u_segs, int v_segs) {
        for (int row = 0; row < v_segs; ++row) {
            for (int col = 0; col < u_segs; ++col) {
                int32_t verts[4] = {
                    grid(row,     col),
                    grid(row,     col + 1),
                    grid(row + 1, col + 1),
                    grid(row + 1, col),
                };
                int32_t face_idx = (int32_t)mesh.faces.size();
                int32_t he_base  = (int32_t)mesh.half_edges.size();
                mesh.faces.push_back({he_base});
                mesh.half_edges.resize(he_base + 4);
                for (int i = 0; i < 4; ++i) {
                    int32_t cur = he_base + i;
                    mesh.half_edges[cur] = {verts[i], -1,
                        he_base + (i + 1) % 4, he_base + (i + 3) % 4, face_idx};
                    if (mesh.vertices[verts[i]].half_edge == -1)
                        mesh.vertices[verts[i]].half_edge = cur;
                    edge_map[{verts[i], verts[(i + 1) % 4]}] = cur;
                }
            }
        }
    };

    build_quads(bottom, ws, ds);
    build_quads(top,    ws, ds);
    build_quads(front,  ws, hs);
    build_quads(back,   ws, hs);
    build_quads(left,   ds, hs);
    build_quads(right,  ds, hs);

    for (auto &[key, he] : edge_map) {
        auto it = edge_map.find({key.b, key.a});
        if (it != edge_map.end() && mesh.half_edges[he].twin == -1) {
            mesh.half_edges[he].twin         = it->second;
            mesh.half_edges[it->second].twin = he;
        }
    }
}

} 
