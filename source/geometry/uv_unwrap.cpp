#define _USE_MATH_DEFINES
#include "uv_unwrap.h"

#include <eigen3/Eigen/Sparse>
#include <eigen3/Eigen/SparseQR>
#include <queue>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <cmath>
#include <algorithm>

using namespace godot;

namespace gomo {
namespace {

std::vector<std::vector<int32_t>> find_islands(const HalfEdgeMesh &mesh) {
    int32_t n = mesh.face_count();
    std::vector<bool> visited(n, false);
    std::vector<std::vector<int32_t>> islands;

    for (int32_t start = 0; start < n; ++start) {
        if (visited[start] || mesh.faces[start].half_edge == -1) {
            visited[start] = true;
            continue;
        }
        std::vector<int32_t> island;
        std::queue<int32_t> q;
        q.push(start);
        visited[start] = true;
        while (!q.empty()) {
            int32_t fi = q.front(); q.pop();
            island.push_back(fi);
            int32_t he = mesh.faces[fi].half_edge;
            do {
                if (!mesh.half_edges[he].seam) {
                    int32_t twin = mesh.half_edges[he].twin;
                    if (twin != -1) {
                        int32_t nfi = mesh.half_edges[twin].face;
                        if (nfi >= 0 && !visited[nfi]) {
                            visited[nfi] = true;
                            q.push(nfi);
                        }
                    }
                }
                he = mesh.half_edges[he].next;
            } while (he != mesh.faces[fi].half_edge);
        }
        if (!island.empty())
            islands.push_back(std::move(island));
    }
    return islands;
}

struct TriInfo {
    int32_t vi[3];
    int32_t he[3];
};

void lscm_island(HalfEdgeMesh &mesh, const std::vector<int32_t> &island_faces) {
    using SpMat   = Eigen::SparseMatrix<double>;
    using Triplet = Eigen::Triplet<double>;

    // --- Collect all half-edges in this island ---
    std::unordered_set<int32_t> island_he_set;
    for (int32_t fi : island_faces) {
        int32_t he = mesh.faces[fi].half_edge;
        do {
            island_he_set.insert(he);
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[fi].half_edge);
    }

    // --- UV vertex splitting ---
    // he.vertex is the SOURCE of the half-edge (start vertex, not destination).
    // Half-edges starting at V share a UV vertex iff connected around V without crossing a seam.
    //
    // Forward:  from h (source=V), cross edge h → nxt = h.twin.next (source=V in adj face).
    //           Stop if h.seam.
    // Backward: from h (source=V), cross h.prev → prev_h = h.prev.twin (source=V in prev face).
    //           Stop if h.prev.seam.

    std::unordered_map<int32_t, int32_t> he_to_uv;
    std::vector<int32_t> uv_to_vert;

    for (int32_t start_he : island_he_set) {
        if (he_to_uv.count(start_he)) continue;

        int32_t V = mesh.half_edges[start_he].vertex;
        int32_t uv_idx = (int32_t)uv_to_vert.size();
        uv_to_vert.push_back(V);
        he_to_uv[start_he] = uv_idx;

        // Forward: h -> h.twin.next -> ...
        {
            int32_t h = start_he;
            while (true) {
                if (mesh.half_edges[h].seam) break;
                int32_t tw = mesh.half_edges[h].twin;
                if (tw == -1) break;
                int32_t nxt = mesh.half_edges[tw].next;
                if (!island_he_set.count(nxt) || he_to_uv.count(nxt)) break;
                he_to_uv[nxt] = uv_idx;
                h = nxt;
            }
        }

        // Backward: h -> h.prev.twin -> ...
        {
            int32_t h = start_he;
            while (true) {
                int32_t prev = mesh.half_edges[h].prev;
                if (mesh.half_edges[prev].seam) break;
                int32_t prev_tw = mesh.half_edges[prev].twin;
                if (prev_tw == -1) break;
                if (!island_he_set.count(prev_tw) || he_to_uv.count(prev_tw)) break;
                he_to_uv[prev_tw] = uv_idx;
                h = prev_tw;
            }
        }
    }

    // --- Triangulate faces ---
    std::vector<TriInfo> tris;

    for (int32_t fi : island_faces) {
        std::vector<int32_t> fhe, fvi;
        int32_t he = mesh.faces[fi].half_edge;
        do {
            fhe.push_back(he);
            fvi.push_back(he_to_uv[he]);
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[fi].half_edge);

        for (int i = 1; i + 1 < (int)fhe.size(); ++i) {
            TriInfo t;
            t.vi[0] = fvi[0];   t.he[0] = fhe[0];
            t.vi[1] = fvi[i];   t.he[1] = fhe[i];
            t.vi[2] = fvi[i+1]; t.he[2] = fhe[i+1];
            tris.push_back(t);
        }
    }

    int32_t n = (int32_t)uv_to_vert.size();
    if (n < 2 || tris.empty()) return;

    // --- Choose pin vertices: farthest pair via two-pass diameter approx ---
    int32_t pin_a = 0, pin_b = 1;
    {
        auto farthest_from = [&](int32_t src) -> int32_t {
            const Vector3 &ps = mesh.vertices[uv_to_vert[src]].position;
            int32_t best = (src == 0) ? 1 : 0;
            float best_d = (mesh.vertices[uv_to_vert[best]].position - ps).length_squared();
            for (int32_t i = 0; i < n; ++i) {
                if (i == src) continue;
                float d = (mesh.vertices[uv_to_vert[i]].position - ps).length_squared();
                if (d > best_d) { best_d = d; best = i; }
            }
            return best;
        };
        pin_a = farthest_from(0);
        pin_b = farthest_from(pin_a);
    }

    // --- Build free vertex mapping ---
    std::vector<int32_t> local_to_free(n, -1);
    std::vector<int32_t> free_list;
    for (int32_t i = 0; i < n; ++i) {
        if (i == pin_a || i == pin_b) continue;
        local_to_free[i] = (int32_t)free_list.size();
        free_list.push_back(i);
    }
    int32_t nf = (int32_t)free_list.size();

    std::vector<double> pin_u(n, 0.0), pin_v(n, 0.0);
    pin_u[pin_b] = 1.0;

    if (nf == 0) {
        for (int32_t fi : island_faces) {
            int32_t he = mesh.faces[fi].half_edge;
            do {
                int32_t uvi = he_to_uv[he];
                mesh.half_edges[he].uv = {(float)pin_u[uvi], (float)pin_v[uvi]};
                he = mesh.half_edges[he].next;
            } while (he != mesh.faces[fi].half_edge);
        }
        return;
    }

    // --- Build LSCM sparse system: 2 rows per triangle ---
    int32_t n_rows = (int32_t)tris.size() * 2;
    int32_t n_cols = nf * 2;

    std::vector<Triplet> trips;
    trips.reserve(n_rows * 6);
    Eigen::VectorXd rhs(n_rows);
    rhs.setZero();

    for (int32_t ti = 0; ti < (int32_t)tris.size(); ++ti) {
        int ia = tris[ti].vi[0], ib = tris[ti].vi[1], ic = tris[ti].vi[2];

        Vector3 Pa = mesh.vertices[uv_to_vert[ia]].position;
        Vector3 Pb = mesh.vertices[uv_to_vert[ib]].position;
        Vector3 Pc = mesh.vertices[uv_to_vert[ic]].position;

        Vector3 AB  = Pb - Pa;
        float   s   = AB.length();
        if (s < 1e-8f) continue;
        Vector3 e1  = AB / s;
        Vector3 nrm = AB.cross(Pc - Pa);
        float   nlen = nrm.length();
        if (nlen < 1e-10f) continue;
        Vector3 e2  = (nrm / nlen).cross(e1);

        float p    = (Pc - Pa).dot(e1);
        float q    = (Pc - Pa).dot(e2);
        float area = 0.5f * s * q;
        if (std::abs(area) < 1e-10f) continue;

        double w = 1.0 / std::sqrt(std::abs((double)area));

        struct C { int vi; double cu, cv; };
        C eq1[3] = {{ia, q,   p-s}, {ib, -q,  -p}, {ic,  0,   s}};
        C eq2[3] = {{ia, s-p, q  }, {ib,  p,  -q}, {ic, -s,   0}};

        for (int eq = 0; eq < 2; ++eq) {
            int row = ti * 2 + eq;
            const C *c = (eq == 0) ? eq1 : eq2;
            for (int k = 0; k < 3; ++k) {
                int    vi = c[k].vi;
                double cu = w * c[k].cu;
                double cv = w * c[k].cv;
                if (vi == pin_a || vi == pin_b) {
                    rhs[row] -= cu * pin_u[vi] + cv * pin_v[vi];
                } else {
                    int fi_u = local_to_free[vi];
                    int fi_v = fi_u + nf;
                    if (cu != 0.0) trips.push_back({row, fi_u, cu});
                    if (cv != 0.0) trips.push_back({row, fi_v, cv});
                }
            }
        }
    }

    // --- Solve least-squares via SparseQR ---
    SpMat A(n_rows, n_cols);
    A.setFromTriplets(trips.begin(), trips.end());

    Eigen::SparseQR<SpMat, Eigen::COLAMDOrdering<int>> solver;
    solver.compute(A);
    if (solver.info() != Eigen::Success) return;
    Eigen::VectorXd x = solver.solve(rhs);
    if (solver.info() != Eigen::Success) return;

    // --- Assemble full UV array ---
    std::vector<double> U(n), V(n);
    U[pin_a] = pin_u[pin_a]; V[pin_a] = pin_v[pin_a];
    U[pin_b] = pin_u[pin_b]; V[pin_b] = pin_v[pin_b];
    for (int32_t i = 0; i < nf; ++i) {
        U[free_list[i]] = x[i];
        V[free_list[i]] = x[i + nf];
    }

    // --- Write UVs ---
    for (int32_t fi : island_faces) {
        int32_t he = mesh.faces[fi].half_edge;
        do {
            int32_t uvi = he_to_uv[he];
            mesh.half_edges[he].uv = {(float)U[uvi], (float)V[uvi]};
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[fi].half_edge);
    }
}

void pack_islands(HalfEdgeMesh &mesh, const std::vector<std::vector<int32_t>> &islands) {
    struct BB { float mn_u, mn_v, mx_u, mx_v; int idx; };
    std::vector<BB> bbs;

    for (int k = 0; k < (int)islands.size(); ++k) {
        float mn_u = 1e38f, mn_v = 1e38f, mx_u = -1e38f, mx_v = -1e38f;
        for (int32_t fi : islands[k]) {
            int32_t he = mesh.faces[fi].half_edge;
            do {
                Vector2 uv = mesh.half_edges[he].uv;
                mn_u = std::min(mn_u, uv.x); mx_u = std::max(mx_u, uv.x);
                mn_v = std::min(mn_v, uv.y); mx_v = std::max(mx_v, uv.y);
                he = mesh.half_edges[he].next;
            } while (he != mesh.faces[fi].half_edge);
        }
        if (mn_u > mx_u) continue;
        bbs.push_back({mn_u, mn_v, mx_u, mx_v, k});
    }
    if (bbs.empty()) return;

    std::sort(bbs.begin(), bbs.end(), [](const BB &a, const BB &b) {
        return (a.mx_v - a.mn_v) > (b.mx_v - b.mn_v);
    });

    const float pad = 0.005f;

    float total_area = 0;
    for (auto &bb : bbs)
        total_area += (bb.mx_u - bb.mn_u + pad) * (bb.mx_v - bb.mn_v + pad);
    float side = std::sqrt(total_area) * 1.15f;

    struct Placement { float ox, oy, mn_u, mn_v; int idx; };
    std::vector<Placement> placements;

    float cx = 0, cy = 0, row_h = 0;
    for (auto &bb : bbs) {
        float w = bb.mx_u - bb.mn_u + pad;
        float h = bb.mx_v - bb.mn_v + pad;
        if (cx + w > side && cx > 0) { cy += row_h; cx = 0; row_h = 0; }
        placements.push_back({cx, cy, bb.mn_u, bb.mn_v, bb.idx});
        cx += w;
        row_h = std::max(row_h, h);
    }
    float total_h = cy + row_h;
    float norm = std::max(side, total_h);
    if (norm < 1e-8f) return;

    for (auto &pl : placements) {
        for (int32_t fi : islands[pl.idx]) {
            int32_t he = mesh.faces[fi].half_edge;
            do {
                Vector2 &uv = mesh.half_edges[he].uv;
                uv.x = (pl.ox + (uv.x - pl.mn_u) + pad * 0.5f) / norm;
                uv.y = (pl.oy + (uv.y - pl.mn_v) + pad * 0.5f) / norm;
                he = mesh.half_edges[he].next;
            } while (he != mesh.faces[fi].half_edge);
        }
    }
}

// Additive only — never clears user-marked seams.
static void mark_angle_seams(HalfEdgeMesh &mesh, float cos_threshold = 0.5f) {
    auto face_normal = [&](int32_t fi) -> Vector3 {
        int32_t h0 = mesh.faces[fi].half_edge;
        int32_t h1 = mesh.half_edges[h0].next;
        int32_t h2 = mesh.half_edges[h1].next;
        Vector3 a = mesh.vertices[mesh.half_edges[h0].vertex].position;
        Vector3 b = mesh.vertices[mesh.half_edges[h1].vertex].position;
        Vector3 c = mesh.vertices[mesh.half_edges[h2].vertex].position;
        Vector3 n = (b - a).cross(c - a);
        float   l = n.length();
        return l > 1e-8f ? n / l : Vector3{};
    };

    for (int32_t i = 0; i < mesh.half_edge_count(); ++i) {
        auto &he = mesh.half_edges[i];
        int32_t twin = he.twin;
        if (twin < 0 || twin <= i) continue;
        if (he.face < 0 || mesh.half_edges[twin].face < 0) continue;
        bool sharp = face_normal(he.face).dot(face_normal(mesh.half_edges[twin].face)) < cos_threshold;
        if (sharp) {
            he.seam                    = true;
            mesh.half_edges[twin].seam = true;
        }
    }
}

} // anonymous namespace

void toggle_seam(HalfEdgeMesh &mesh, int32_t he_idx) {
    if (he_idx < 0 || he_idx >= mesh.half_edge_count()) return;
    bool val = !mesh.half_edges[he_idx].seam;
    mesh.half_edges[he_idx].seam = val;
    int32_t twin = mesh.half_edges[he_idx].twin;
    if (twin != -1) mesh.half_edges[twin].seam = val;
}

void unwrap_uvs(HalfEdgeMesh &mesh) {
    mark_angle_seams(mesh);
    auto islands = find_islands(mesh);
    for (auto &island : islands)
        lscm_island(mesh, island);
    pack_islands(mesh, islands);
}

} // namespace gomo
