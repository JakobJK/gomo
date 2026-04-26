#include "command.h"

namespace gomo {

void CommandHistory::_push_undo(std::unique_ptr<Command> cmd) {
    _undo_stack.push_back(std::move(cmd));
    if ((int)_undo_stack.size() > MAX_HISTORY)
        _undo_stack.erase(_undo_stack.begin());
}

void CommandHistory::execute(HalfEdgeMesh &mesh, std::unique_ptr<Command> cmd) {
    cmd->do_it(mesh);
    _redo_stack.clear();
    _push_undo(std::move(cmd));
}

void CommandHistory::record(std::unique_ptr<Command> cmd) {
    _redo_stack.clear();
    _push_undo(std::move(cmd));
}

bool CommandHistory::undo(HalfEdgeMesh &mesh) {
    if (_undo_stack.empty()) return false;
    auto cmd = std::move(_undo_stack.back());
    _undo_stack.pop_back();
    cmd->undo_it(mesh);
    _redo_stack.push_back(std::move(cmd));
    return true;
}

bool CommandHistory::redo(HalfEdgeMesh &mesh) {
    if (_redo_stack.empty()) return false;
    auto cmd = std::move(_redo_stack.back());
    _redo_stack.pop_back();
    cmd->redo_it(mesh);
    _undo_stack.push_back(std::move(cmd));
    return true;
}

void CommandHistory::clear() {
    _undo_stack.clear();
    _redo_stack.clear();
}

}
