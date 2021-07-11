#include "IRVisitor.h"
#include "Stmts.h"
#include <map>
#include <functional>

namespace zfx {

struct GatherLocalLoad : Visitor<GatherLocalLoad> {
    using visit_stmt_types = std::tuple
        < AsmLocalLoadStmt
        >;

    std::map<int, int> last_load;

    void visit(AsmLocalLoadStmt *stmt) {
        last_load[stmt->mem] = std::max(last_load[stmt->mem], stmt->id);
    }
};

struct KillLocalStore : Visitor<KillLocalStore> {
    using visit_stmt_types = std::tuple
        < AsmLocalLoadStmt
        , AsmLocalStoreStmt
        , Statement
        >;

    std::unique_ptr<IR> ir = std::make_unique<IR>();

    struct StoreRAII {
        int reg = -1;
        std::function<void()> dtor;

        StoreRAII() = default;
        ~StoreRAII() { dtor(); }
        StoreRAII &operator=(StoreRAII const &) = default;

        template <class F>
        StoreRAII(int reg, F const &dtor)
            : reg(reg), dtor(dtor) {}
    };

    std::map<int, int> last_load;
    std::map<int, StoreRAII> storer;

    void visit(AsmLocalLoadStmt *stmt) {
        if (auto it = storer.find(stmt->mem); it != storer.end()) {
            storer.erase(it);
            return;
        }
        visit((Statement *)stmt);
    }

    void visit(AsmLocalStoreStmt *stmt) {
        auto it = last_load.find(stmt->mem);
        if (it == last_load.end())
            return;
        if (stmt->id > it->second)
            return;
        auto hole = ir->make_hole_back();
        storer[stmt->mem] = StoreRAII(stmt->val, [hole, stmt]() {
            hole.place<AsmLocalStoreStmt>(stmt->mem, stmt->val);
        });
    }

    void visit(Statement *stmt) {
        ir->push_clone_back(stmt);
    }
};

std::unique_ptr<IR> apply_kill_local_store(IR *ir) {
    GatherLocalLoad gather;
    gather.apply(ir);
    KillLocalStore visitor;
    visitor.last_load = gather.last_load;
    visitor.apply(ir);
    return std::move(visitor.ir);
}

}
