#pragma once

#include "../half_edge_mesh.h"

namespace gomo {

void build_cylinder(HalfEdgeMesh &mesh, int32_t sides = 8, float radius = 1.0f, float height = 2.0f);

} // namespace gomo
