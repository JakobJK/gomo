#include "gomo_mesh.h"

#include "../geometry/mesh_ops.h"
#include "../geometry/mesh_commands.h"

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
}

void HalfEdgeMesh::build_box() {
    gomo::build_box(_mesh);
    _history.clear();
}

void HalfEdgeMesh::build_sphere(int32_t lat_segments, int32_t lon_segments) {
    gomo::build_sphere(_mesh, lat_segments, lon_segments);
    _history.clear();
}

// --- Conversion ---
Ref<ArrayMesh> HalfEdgeMesh::to_array_mesh() const {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    for (int32_t fi = 0; fi < _mesh.face_count(); ++fi) {
        if (_mesh.faces[fi].half_edge == -1) continue;

        auto fv_indices = gomo::get_face_vertex_indices(_mesh, fi);
        if ((int)fv_indices.size() < 3) continue;

        std::vector<Vector3> fv;
        fv.reserve(fv_indices.size());
        for (int32_t vi : fv_indices)
            fv.push_back(_mesh.vertices[vi].position);

        gomo::FaceFrame frame    = gomo::compute_face_frame(_mesh, fi);
        Vector3         geo_norm = gomo::get_face_normal(_mesh, fi);

        PackedVector3Array verts, norms;
        PackedVector2Array uvs;
        PackedFloat32Array tans;

        auto add_vert = [&](const Vector3 &p) {
            verts.push_back(p);
            norms.push_back(geo_norm);
            Vector3 d = p - frame.origin;
            float u = (frame.width  > 1e-6f) ? d.dot(frame.tangent)   / frame.width  : 0.0f;
            float v = (frame.height > 1e-6f) ? d.dot(frame.bitangent) / frame.height : 0.0f;
            uvs.push_back({u, v});
            tans.push_back(frame.tangent.x);
            tans.push_back(frame.tangent.y);
            tans.push_back(frame.tangent.z);
            tans.push_back(1.0f);
        };

        for (int i = 1; i + 1 < (int)fv.size(); ++i) {
            add_vert(fv[0]);
            add_vert(fv[i + 1]);
            add_vert(fv[i]);
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
PackedInt32Array HalfEdgeMesh::extrude_edge(int32_t half_edge_index) {
    ERR_FAIL_INDEX_V(half_edge_index, _mesh.half_edge_count(), PackedInt32Array());
    ERR_FAIL_COND_V_MSG(_mesh.half_edges[half_edge_index].twin != -1, PackedInt32Array(),
                        "extrude_edge requires a boundary half-edge (twin == -1)");
    auto  cmd = std::make_unique<gomo::ExtrudeEdgeCommand>(half_edge_index);
    auto *raw = cmd.get();
    _history.execute(_mesh, std::move(cmd));
    PackedInt32Array out;
    for (int32_t v : raw->new_vertex_indices()) out.push_back(v);
    return out;
}

PackedInt32Array HalfEdgeMesh::extrude_face(int32_t face_idx) {
    ERR_FAIL_INDEX_V(face_idx, _mesh.face_count(), PackedInt32Array());
    auto  cmd = std::make_unique<gomo::ExtrudeFaceCommand>(face_idx);
    auto *raw = cmd.get();
    _history.execute(_mesh, std::move(cmd));
    PackedInt32Array out;
    for (int32_t v : raw->new_vertex_indices()) out.push_back(v);
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

// --- Sculpting ---
void HalfEdgeMesh::paint_at(Vector3 hit_pos, float strength, float world_radius) {
    gomo::paint_at(_mesh, hit_pos, strength, world_radius);
}

void HalfEdgeMesh::flatten_at(Vector3 hit_pos, float strength, float world_radius) {
    gomo::flatten_at(_mesh, hit_pos, strength, world_radius);
}

void HalfEdgeMesh::begin_tilt_stroke() {
    _pending_tilt_stroke = std::make_unique<gomo::TiltStrokeCommand>();
    _pending_tilt_stroke->capture_before(_mesh);
}

void HalfEdgeMesh::end_tilt_stroke() {
    if (!_pending_tilt_stroke) return;
    _pending_tilt_stroke->capture_after(_mesh);
    _history.record(std::move(_pending_tilt_stroke));
}

void HalfEdgeMesh::restore_tilt_to_stroke_base() {
    if (_pending_tilt_stroke)
        _pending_tilt_stroke->restore_before(_mesh);
}

Ref<Image> HalfEdgeMesh::get_face_normal_map(int32_t face_idx) const {
    ERR_FAIL_INDEX_V(face_idx, _mesh.face_count(), Ref<Image>());
    const int S = gomo::Face::HF_SIZE;

    gomo::FaceFrame f   = gomo::compute_face_frame(_mesh, face_idx);
    Vector3         geo = gomo::get_face_normal(_mesh, face_idx);

    const auto &tilt = _mesh.faces[face_idx].tilt;
    PackedByteArray data;
    data.resize(S * S * 4);
    uint8_t *ptr = data.ptrw();

    auto enc = [](float v) -> uint8_t {
        return (uint8_t)std::max(0, std::min(255, (int)((v * 0.5f + 0.5f) * 255.0f)));
    };

    for (int y = 0; y < S; ++y) {
        for (int x = 0; x < S; ++x) {
            float tu = tilt[(y * S + x) * 2 + 0];
            float tv = tilt[(y * S + x) * 2 + 1];
            float tz = std::sqrt(std::max(0.0f, 1.0f - tu * tu - tv * tv));
            Vector3 world_n = (geo * tz + f.tangent * tu + f.bitangent * tv).normalized();
            int i = (y * S + x) * 4;
            ptr[i + 0] = enc(world_n.x);
            ptr[i + 1] = enc(world_n.y);
            ptr[i + 2] = enc(world_n.z);
            ptr[i + 3] = 255;
        }
    }

    return Image::create_from_data(S, S, false, Image::FORMAT_RGBA8, data);
}

// --- Undo / redo ---

bool HalfEdgeMesh::undo() { return _history.undo(_mesh); }
bool HalfEdgeMesh::redo() { return _history.redo(_mesh); }
bool HalfEdgeMesh::can_undo() const { return _history.can_undo(); }
bool HalfEdgeMesh::can_redo() const { return _history.can_redo(); }

void HalfEdgeMesh::clear() {
    _mesh.clear();
    _history.clear();
}

// --- Bindings ---

void HalfEdgeMesh::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_from_triangles", "positions"), &HalfEdgeMesh::build_from_triangles);
    ClassDB::bind_method(D_METHOD("build_box"),                         &HalfEdgeMesh::build_box);
    ClassDB::bind_method(D_METHOD("build_sphere", "lat_segments", "lon_segments"), &HalfEdgeMesh::build_sphere);
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
    ClassDB::bind_method(D_METHOD("extrude_edge", "half_edge_index"),     &HalfEdgeMesh::extrude_edge);
    ClassDB::bind_method(D_METHOD("extrude_face", "face_idx"),            &HalfEdgeMesh::extrude_face);
    ClassDB::bind_method(D_METHOD("delete_face",  "face_idx"),            &HalfEdgeMesh::delete_face);
    ClassDB::bind_method(D_METHOD("record_move_vertices", "indices", "old_positions"), &HalfEdgeMesh::record_move_vertices);
    ClassDB::bind_method(D_METHOD("paint_at",   "hit_pos", "strength", "world_radius"), &HalfEdgeMesh::paint_at);
    ClassDB::bind_method(D_METHOD("flatten_at", "hit_pos", "strength", "world_radius"), &HalfEdgeMesh::flatten_at);
    ClassDB::bind_method(D_METHOD("begin_tilt_stroke"),                   &HalfEdgeMesh::begin_tilt_stroke);
    ClassDB::bind_method(D_METHOD("end_tilt_stroke"),                     &HalfEdgeMesh::end_tilt_stroke);
    ClassDB::bind_method(D_METHOD("restore_tilt_to_stroke_base"),         &HalfEdgeMesh::restore_tilt_to_stroke_base);
    ClassDB::bind_method(D_METHOD("get_face_normal_map", "face_idx"),     &HalfEdgeMesh::get_face_normal_map);
    ClassDB::bind_method(D_METHOD("undo"),      &HalfEdgeMesh::undo);
    ClassDB::bind_method(D_METHOD("redo"),      &HalfEdgeMesh::redo);
    ClassDB::bind_method(D_METHOD("can_undo"),  &HalfEdgeMesh::can_undo);
    ClassDB::bind_method(D_METHOD("can_redo"),  &HalfEdgeMesh::can_redo);
    ClassDB::bind_method(D_METHOD("clear"),     &HalfEdgeMesh::clear);
}
