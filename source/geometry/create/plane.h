#pragma once

#include "../half_edge_mesh.h"

namespace gomo {

void build_plane(HalfEdgeMesh &mesh,
                          float width, float depth,
                          int32_t width_segments, int32_t depth_segments);

}
