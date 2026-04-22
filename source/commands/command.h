#pragma once

#include "../geometry/half_edge_mesh.h"
#include <memory>
#include <vector>

namespace gomo {

// ---------------------------------------------------------------------------
// Base — mirrors Maya's MPxCommand interface.
// do_it()   : first execution; capture arguments and apply the operation.
// redo_it() : re-execution after undo.
// undo_it() : reverse the operation using state captured in do_it().
// ---------------------------------------------------------------------------

class Command {
public:
    virtual ~Command() = default;
    virtual void do_it(HalfEdgeMesh &mesh)   = 0;
    virtual void redo_it(HalfEdgeMesh &mesh) = 0;
    virtual void undo_it(HalfEdgeMesh &mesh) = 0;
};

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

class CommandHistory {
public:
    void execute(HalfEdgeMesh &mesh, std::unique_ptr<Command> cmd);
    void record(std::unique_ptr<Command> cmd);

    bool undo(HalfEdgeMesh &mesh);
    bool redo(HalfEdgeMesh &mesh);
    bool can_undo() const { return !_undo_stack.empty(); }
    bool can_redo() const { return !_redo_stack.empty(); }
    void clear();

private:
    static constexpr int MAX_HISTORY = 100;
    std::vector<std::unique_ptr<Command>> _undo_stack;
    std::vector<std::unique_ptr<Command>> _redo_stack;

    void _push_undo(std::unique_ptr<Command> cmd);
};

} // namespace gomo
