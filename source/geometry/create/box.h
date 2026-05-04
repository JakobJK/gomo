#pragma once

#include "../half_edge_mesh.h"

namespace gomo {

void build_box(HalfEdgeMesh &mesh,
                          float width, float height, float depth,
                          int32_t width_segments, int32_t height_segments, int32_t depth_segments);

} // namespace gomo
