#include "gomo_mesh.h"

#include "../geometry/mesh_ops.h"
#include "../geometry/mesh_commands.h"
#include "../geometry/create/box.h"
#include "../geometry/create/cylinder.h"
#include "../geometry/subdivide.h"
#include "../geometry/bake.h"
#include "../geometry/uv_unwrap.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <cstring>

using namespace godot;

// --- Construction ---
void HalfEdgeMesh::build_from_triangles(const PackedVector3Array &positions) {
    gomo::build_from_triangles(_mesh, positions.ptr(), positions.size());
    _history.clear();
    _uvs_valid = false;
}

void HalfEdgeMesh::build_box(float width, float height, float depth,
                              int32_t width_segments, int32_t height_segments, int32_t depth_segments) {
    gomo::build_box(_mesh, width, height, depth, width_segments, height_segments, depth_segments);
    _history.clear();
    gomo::unwrap_uvs(_mesh);
    _uvs_valid = true;
}

void HalfEdgeMesh::build_sphere(int32_t lat_segments, int32_t lon_segments) {
    gomo::build_sphere(_mesh, lat_segments, lon_segments);
    _history.clear();
    _uvs_valid = false;
}

void HalfEdgeMesh::build_cylinder(int32_t sides, float radius, float height) {
    gomo::build_cylinder(_mesh, sides, radius, height);
    _history.clear();
    _uvs_valid = false;
}

// --- Conversion ---
Ref<ArrayMesh> HalfEdgeMesh::to_array_mesh() const {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    // Area-weighted smooth vertex normals
    std::vector<Vector3> vert_norm(_mesh.vertex_count(), Vector3(0, 0, 0));
    for (int32_t fi = 0; fi < _mesh.face_count(); ++fi) {
        if (_mesh.faces[fi].half_edge == -1) continue;
        std::vector<int32_t> fv_idx;
        int32_t he = _mesh.faces[fi].half_edge;
        do {
            fv_idx.push_back(_mesh.half_edges[he].vertex);
            he = _mesh.half_edges[he].next;
        } while (he != _mesh.faces[fi].half_edge);
        for (int i = 1; i + 1 < (int)fv_idx.size(); ++i) {
            Vector3 e1 = _mesh.vertices[fv_idx[i]].position   - _mesh.vertices[fv_idx[0]].position;
            Vector3 e2 = _mesh.vertices[fv_idx[i+1]].position - _mesh.vertices[fv_idx[0]].position;
            Vector3 wN = e1.cross(e2);
            vert_norm[fv_idx[0]]   += wN;
            vert_norm[fv_idx[i]]   += wN;
            vert_norm[fv_idx[i+1]] += wN;
        }
    }
    for (auto &n : vert_norm) {
        float len = n.length();
        n = (len > 1e-10f) ? n / len : Vector3(0, 1, 0);
    }

    for (int32_t fi = 0; fi < _mesh.face_count(); ++fi) {
        if (_mesh.faces[fi].half_edge == -1) continue;

        // Collect half-edges, positions, and UVs in face order
        std::vector<int32_t> fhe;
        std::vector<Vector3> fv;
        std::vector<Vector2> fv_uv;
        int32_t he = _mesh.faces[fi].half_edge;
        do {
            fhe.push_back(he);
            int32_t vi = _mesh.half_edges[he].vertex;
            fv.push_back(_mesh.vertices[vi].position);
            fv_uv.push_back(_mesh.half_edges[he].uv);
            he = _mesh.half_edges[he].next;
        } while (he != _mesh.faces[fi].half_edge);
        if ((int)fv.size() < 3) continue;

        Vector3 geo_norm = gomo::get_face_normal(_mesh, fi);
        Vector3 geom_tan = (fv[1] - fv[0]).normalized();
        Vector3 geom_bit = geo_norm.cross(geom_tan).normalized();

        // Geometric tangent for this face: first edge projected off face normal
        Vector3 T_face = (fv[1] - fv[0]);
        T_face = (T_face - geo_norm * geo_norm.dot(T_face)).normalized();

        Vector3 uv_origin;
        float   uv_width = 0.0f, uv_height = 0.0f;
        if (!_uvs_valid) {
            float min_u = 1e38f, max_u = -1e38f, min_v = 1e38f, max_v = -1e38f;
            for (auto &p : fv) {
                Vector3 d = p - fv[0];
                float u = d.dot(geom_tan), v = d.dot(geom_bit);
                if (u < min_u) min_u = u;  if (u > max_u) max_u = u;
                if (v < min_v) min_v = v;  if (v > max_v) max_v = v;
            }
            uv_origin = fv[0] + geom_tan * min_u + geom_bit * min_v;
            uv_width  = max_u - min_u;
            uv_height = max_v - min_v;
        }

        PackedVector3Array verts, norms;
        PackedVector2Array uvs;
        PackedFloat32Array tans;

        auto get_uv = [&](int corner) -> Vector2 {
            if (_uvs_valid) return _mesh.half_edges[fhe[corner]].uv;
            const Vector3 &p = fv[corner];
            Vector3 d = p - uv_origin;
            float u = (uv_width  > 1e-6f) ? d.dot(geom_tan) / uv_width  : 0.0f;
            float v = (uv_height > 1e-6f) ? d.dot(geom_bit)  / uv_height : 0.0f;
            return {u, v};
        };

        auto add_vert = [&](int corner) {
            int32_t vi = _mesh.half_edges[fhe[corner]].vertex;
            const Vector3 &N = vert_norm[vi];
            Vector3 T = T_face - N * N.dot(T_face);
            float tlen = T.length();
            T = (tlen > 1e-10f) ? T / tlen : N.cross(Vector3(0, 1, 0)).normalized();
            verts.push_back(fv[corner]);
            norms.push_back(N);
            uvs.push_back(get_uv(corner));
            tans.push_back(T.x); tans.push_back(T.y); tans.push_back(T.z); tans.push_back(1.0f);
        };

        for (int i = 1; i + 1 < (int)fv.size(); ++i) {
            int c0 = 0, c1 = i + 1, c2 = i;
            add_vert(c0); add_vert(c1); add_vert(c2);
        }

        Array arrays;
        arrays.resize(ArrayMesh::ARRAY_MAX);
        arrays[ArrayMesh::ARRAY_VERTEX]  = verts;
        arrays[ArrayMesh::ARRAY_NORMAL]  = norms;
        arrays[ArrayMesh::ARRAY_TEX_UV]  = uvs;
        arrays[ArrayMesh::ARRAY_TANGENT] = tans;
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    }

    return mesh;
}

// --- Counts ---

int32_t HalfEdgeMesh::get_vertex_count() const { return _mesh.vertex_count(); }
int32_t HalfEdgeMesh::get_edge_count()   const { return _mesh.half_edge_count(); }
int32_t HalfEdgeMesh::get_face_count()   const { return _mesh.face_count(); }

// --- Vertex accessors ---
Vector3 HalfEdgeMesh::get_vertex_position(int32_t idx) const {
    ERR_FAIL_INDEX_V(idx, _mesh.vertex_count(), Vector3());
    return _mesh.vertices[idx].position;
}

void HalfEdgeMesh::set_vertex_position(int32_t idx, Vector3 pos) {
    ERR_FAIL_INDEX(idx, _mesh.vertex_count());
    _mesh.vertices[idx].position = pos;
}

PackedVector3Array HalfEdgeMesh::get_vertex_positions() const {
    PackedVector3Array out;
    out.resize(_mesh.vertex_count());
    for (int32_t i = 0; i < _mesh.vertex_count(); ++i)
        out[i] = _mesh.vertices[i].position;
    return out;
}

// --- Half-edge accessors ---
int32_t HalfEdgeMesh::get_half_edge_vertex(int32_t half_edge_index) const {
    ERR_FAIL_INDEX_V(half_edge_index, _mesh.half_edge_count(), -1);
    return _mesh.half_edges[half_edge_index].vertex;
}

int32_t HalfEdgeMesh::get_half_edge_next(int32_t half_edge_index) const {
    ERR_FAIL_INDEX_V(half_edge_index, _mesh.half_edge_count(), -1);
    return _mesh.half_edges[half_edge_index].next;
}

int32_t HalfEdgeMesh::get_half_edge_twin(int32_t half_edge_index) const {
    ERR_FAIL_INDEX_V(half_edge_index, _mesh.half_edge_count(), -1);
    return _mesh.half_edges[half_edge_index].twin;
}

int32_t HalfEdgeMesh::get_half_edge_face(int32_t half_edge_index) const {
    ERR_FAIL_INDEX_V(half_edge_index, _mesh.half_edge_count(), -1);
    return _mesh.half_edges[half_edge_index].face;
}

// --- Face accessors ---
bool HalfEdgeMesh::is_face_valid(int32_t face_idx) const {
    ERR_FAIL_INDEX_V(face_idx, _mesh.face_count(), false);
    return _mesh.faces[face_idx].half_edge != -1;
}

Vector3 HalfEdgeMesh::get_face_center(int32_t face_idx) const {
    ERR_FAIL_INDEX_V(face_idx, _mesh.face_count(), Vector3());
    return gomo::get_face_center(_mesh, face_idx);
}

Vector3 HalfEdgeMesh::get_face_normal(int32_t face_idx) const {
    ERR_FAIL_INDEX_V(face_idx, _mesh.face_count(), Vector3());
    return gomo::get_face_normal(_mesh, face_idx);
}

PackedInt32Array HalfEdgeMesh::get_face_vertex_indices(int32_t face_idx) const {
    ERR_FAIL_INDEX_V(face_idx, _mesh.face_count(), PackedInt32Array());
    auto indices = gomo::get_face_vertex_indices(_mesh, face_idx);
    PackedInt32Array result;
    for (int32_t v : indices) result.push_back(v);
    return result;
}

int32_t HalfEdgeMesh::pick_face(Vector3 ray_from, Vector3 ray_dir) const {
    return gomo::pick_face(_mesh, ray_from, ray_dir);
}

// --- Topology operations ---
PackedInt32Array HalfEdgeMesh::extrude_edges(PackedInt32Array half_edges) {
    int32_t n = half_edges.size();
    std::vector<int32_t> hes(n);
    for (int32_t i = 0; i < n; ++i) {
        int32_t he = half_edges[i];
        ERR_FAIL_INDEX_V(he, _mesh.half_edge_count(), PackedInt32Array());
        ERR_FAIL_COND_V_MSG(_mesh.half_edges[he].twin != -1, PackedInt32Array(),
                            "extrude_edges requires boundary half-edges (twin == -1)");
        hes[i] = he;
    }
    auto cmd = std::make_unique<gomo::ExtrudeEdgesCommand>(std::move(hes));
    auto *raw = cmd.get();
    _history.execute(_mesh, std::move(cmd));
    PackedInt32Array out;
    for (int32_t i : raw->new_edge_indices()) out.push_back(i);
    return out;
}

PackedInt32Array HalfEdgeMesh::extrude_faces(PackedInt32Array face_indices) {
    int32_t n = face_indices.size();
    std::vector<int32_t> fis(n);
    for (int32_t i = 0; i < n; ++i) {
        int32_t fi = face_indices[i];
        ERR_FAIL_INDEX_V(fi, _mesh.face_count(), PackedInt32Array());
        fis[i] = fi;
    }
    auto cmd = std::make_unique<gomo::ExtrudeFacesCommand>(std::move(fis));
    auto *raw = cmd.get();
    _history.execute(_mesh, std::move(cmd));
    PackedInt32Array out;
    for (int32_t fi : raw->result_face_indices()) out.push_back(fi);
    return out;
}

void HalfEdgeMesh::delete_face(int32_t face_idx) {
    ERR_FAIL_INDEX(face_idx, _mesh.face_count());
    _history.execute(_mesh, std::make_unique<gomo::DeleteFaceCommand>(_mesh, face_idx));
}

// --- Vertex move ---
void HalfEdgeMesh::record_move_vertices(PackedInt32Array indices,
                                         PackedVector3Array old_positions) {
    int32_t n = indices.size();
    std::vector<int32_t>  idx(n);
    std::vector<Vector3>  old_pos(n), new_pos(n);
    for (int32_t i = 0; i < n; ++i) {
        idx[i]     = indices[i];
        old_pos[i] = old_positions[i];
        new_pos[i] = _mesh.vertices[indices[i]].position;
    }
    _history.record(std::make_unique<gomo::MoveVerticesCommand>(
        std::move(idx), std::move(old_pos), std::move(new_pos)));
}

// --- UV unwrapping ---

void HalfEdgeMesh::unwrap_uvs() {
    gomo::unwrap_uvs(_mesh);
    _uvs_valid = true;
}

void HalfEdgeMesh::set_seam(int32_t he_idx, bool is_seam) {
    ERR_FAIL_INDEX(he_idx, _mesh.half_edge_count());
    _mesh.half_edges[he_idx].seam = is_seam;
    int32_t twin = _mesh.half_edges[he_idx].twin;
    if (twin != -1) _mesh.half_edges[twin].seam = is_seam;
}

bool HalfEdgeMesh::get_seam(int32_t he_idx) const {
    ERR_FAIL_INDEX_V(he_idx, _mesh.half_edge_count(), false);
    return _mesh.half_edges[he_idx].seam;
}

void HalfEdgeMesh::set_crease(int32_t he_idx, float weight) {
    ERR_FAIL_INDEX(he_idx, _mesh.half_edge_count());
    _mesh.half_edges[he_idx].crease = weight;
    int32_t twin = _mesh.half_edges[he_idx].twin;
    if (twin != -1) _mesh.half_edges[twin].crease = weight;
}

float HalfEdgeMesh::get_crease(int32_t he_idx) const {
    ERR_FAIL_INDEX_V(he_idx, _mesh.half_edge_count(), 0.0f);
    return _mesh.half_edges[he_idx].crease;
}


PackedVector2Array HalfEdgeMesh::get_uv_edges() const {
    PackedVector2Array result;
    for (int32_t hi = 0; hi < _mesh.half_edge_count(); ++hi) {
        const auto &he = _mesh.half_edges[hi];
        if (he.face == -1) continue;
        // Each half-edge gives one directed UV edge; draw all so seam boundaries appear on both sides
        result.push_back(he.uv);
        result.push_back(_mesh.half_edges[he.next].uv);
    }
    return result;
}

PackedVector2Array HalfEdgeMesh::get_uv_seam_edges() const {
    PackedVector2Array result;
    for (int32_t hi = 0; hi < _mesh.half_edge_count(); ++hi) {
        const auto &he = _mesh.half_edges[hi];
        if (he.face == -1 || !he.seam) continue;
        result.push_back(he.uv);
        result.push_back(_mesh.half_edges[he.next].uv);
    }
    return result;
}

Array HalfEdgeMesh::get_uv_face_polygons() const {
    Array result;
    for (int32_t fi = 0; fi < (int32_t)_mesh.faces.size(); ++fi) {
        int32_t start = _mesh.faces[fi].half_edge;
        if (start == -1) continue;
        PackedVector2Array poly;
        int32_t cur = start;
        do {
            poly.push_back(_mesh.half_edges[cur].uv);
            cur = _mesh.half_edges[cur].next;
        } while (cur != start);
        result.append(poly);
    }
    return result;
}

void HalfEdgeMesh::translate_uvs(PackedVector2Array positions, Vector2 delta, float epsilon) {
    float eps_sq = epsilon * epsilon;
    for (auto &he : _mesh.half_edges) {
        if (he.face == -1) continue;
        for (int i = 0; i < positions.size(); ++i) {
            if (he.uv.distance_squared_to(positions[i]) <= eps_sq) {
                he.uv += delta;
                break;
            }
        }
    }
}

// --- Subdivision preview ---

Ref<ArrayMesh> HalfEdgeMesh::subdivide_to_mesh(int32_t levels) const {
    return gomo::subdivide_to_mesh(_mesh, levels);
}

// --- Normal map baking ---

Ref<Image> HalfEdgeMesh::bake_normal_map(int32_t subdiv_levels, int32_t resolution) const {
    return gomo::bake_normal_map(_mesh, subdiv_levels, resolution);
}

// --- Undo / redo ---

bool HalfEdgeMesh::undo() { return _history.undo(_mesh); }
bool HalfEdgeMesh::redo() { return _history.redo(_mesh); }
bool HalfEdgeMesh::can_undo() const { return _history.can_undo(); }
bool HalfEdgeMesh::can_redo() const { return _history.can_redo(); }

void HalfEdgeMesh::clear() {
    _mesh.clear();
    _history.clear();
    _uvs_valid = false;
}

// --- Bindings ---

void HalfEdgeMesh::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_from_triangles", "positions"), &HalfEdgeMesh::build_from_triangles);
    ClassDB::bind_method(D_METHOD("build_box", "width", "height", "depth", "width_segments", "height_segments", "depth_segments"), &HalfEdgeMesh::build_box);
    ClassDB::bind_method(D_METHOD("build_sphere", "lat_segments", "lon_segments"), &HalfEdgeMesh::build_sphere);
    ClassDB::bind_method(D_METHOD("build_cylinder", "sides", "radius", "height"), &HalfEdgeMesh::build_cylinder);
    ClassDB::bind_method(D_METHOD("to_array_mesh"),                     &HalfEdgeMesh::to_array_mesh);
    ClassDB::bind_method(D_METHOD("get_vertex_count"),                  &HalfEdgeMesh::get_vertex_count);
    ClassDB::bind_method(D_METHOD("get_edge_count"),                    &HalfEdgeMesh::get_edge_count);
    ClassDB::bind_method(D_METHOD("get_face_count"),                    &HalfEdgeMesh::get_face_count);
    ClassDB::bind_method(D_METHOD("get_vertex_position", "idx"),        &HalfEdgeMesh::get_vertex_position);
    ClassDB::bind_method(D_METHOD("set_vertex_position", "idx", "pos"), &HalfEdgeMesh::set_vertex_position);
    ClassDB::bind_method(D_METHOD("get_vertex_positions"),              &HalfEdgeMesh::get_vertex_positions);
    ClassDB::bind_method(D_METHOD("get_half_edge_vertex", "half_edge_index"), &HalfEdgeMesh::get_half_edge_vertex);
    ClassDB::bind_method(D_METHOD("get_half_edge_next",   "half_edge_index"), &HalfEdgeMesh::get_half_edge_next);
    ClassDB::bind_method(D_METHOD("get_half_edge_twin",   "half_edge_index"), &HalfEdgeMesh::get_half_edge_twin);
    ClassDB::bind_method(D_METHOD("get_half_edge_face",   "half_edge_index"), &HalfEdgeMesh::get_half_edge_face);
    ClassDB::bind_method(D_METHOD("is_face_valid",           "face_idx"), &HalfEdgeMesh::is_face_valid);
    ClassDB::bind_method(D_METHOD("get_face_center",         "face_idx"), &HalfEdgeMesh::get_face_center);
    ClassDB::bind_method(D_METHOD("get_face_normal",         "face_idx"), &HalfEdgeMesh::get_face_normal);
    ClassDB::bind_method(D_METHOD("get_face_vertex_indices", "face_idx"), &HalfEdgeMesh::get_face_vertex_indices);
    ClassDB::bind_method(D_METHOD("pick_face", "ray_from", "ray_dir"),    &HalfEdgeMesh::pick_face);
    ClassDB::bind_method(D_METHOD("extrude_edges", "half_edges"),          &HalfEdgeMesh::extrude_edges);
    ClassDB::bind_method(D_METHOD("extrude_faces", "face_indices"),        &HalfEdgeMesh::extrude_faces);
    ClassDB::bind_method(D_METHOD("delete_face",  "face_idx"),            &HalfEdgeMesh::delete_face);
    ClassDB::bind_method(D_METHOD("record_move_vertices", "indices", "old_positions"), &HalfEdgeMesh::record_move_vertices);
    ClassDB::bind_method(D_METHOD("subdivide_to_mesh", "levels"), &HalfEdgeMesh::subdivide_to_mesh);
    ClassDB::bind_method(D_METHOD("bake_normal_map", "subdiv_levels", "resolution"), &HalfEdgeMesh::bake_normal_map);
    ClassDB::bind_method(D_METHOD("unwrap_uvs"),                                    &HalfEdgeMesh::unwrap_uvs);
    ClassDB::bind_method(D_METHOD("set_seam", "half_edge_index", "is_seam"),        &HalfEdgeMesh::set_seam);
    ClassDB::bind_method(D_METHOD("get_seam", "half_edge_index"),                   &HalfEdgeMesh::get_seam);
    ClassDB::bind_method(D_METHOD("set_crease", "half_edge_index", "weight"),       &HalfEdgeMesh::set_crease);
    ClassDB::bind_method(D_METHOD("get_crease", "half_edge_index"),                 &HalfEdgeMesh::get_crease);
    ClassDB::bind_method(D_METHOD("get_uv_edges"),                                  &HalfEdgeMesh::get_uv_edges);
    ClassDB::bind_method(D_METHOD("get_uv_seam_edges"),                             &HalfEdgeMesh::get_uv_seam_edges);
    ClassDB::bind_method(D_METHOD("get_uv_face_polygons"),                          &HalfEdgeMesh::get_uv_face_polygons);
    ClassDB::bind_method(D_METHOD("translate_uvs", "positions", "delta", "epsilon"), &HalfEdgeMesh::translate_uvs);
    ClassDB::bind_method(D_METHOD("undo"),      &HalfEdgeMesh::undo);
    ClassDB::bind_method(D_METHOD("redo"),      &HalfEdgeMesh::redo);
    ClassDB::bind_method(D_METHOD("can_undo"),  &HalfEdgeMesh::can_undo);
    ClassDB::bind_method(D_METHOD("can_redo"),  &HalfEdgeMesh::can_redo);
    ClassDB::bind_method(D_METHOD("clear"),     &HalfEdgeMesh::clear);
}
