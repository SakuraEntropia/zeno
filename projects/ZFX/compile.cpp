#include "program.h"
#include "assemble.h"
#include "ast.h"

auto parse_program(std::string const &code) {
    Parser p(code);
    return p.parse();
}

std::string opchar_to_opcode(std::string const &op) {
}

struct Translator {
    struct Visit {
        std::string lvalue;
        std::string rvalue;

    };

    int regid = 0;
    std::string alloc_register() {
        return "$" + (regid++ % 256);
    }

    void emit(std::string const &str) {
        printf("%s\n", str.c_str());
    }

    std::string lvalue(Visit *vis) {
        if (vis.lvalue.size() == 0) {
            auto reg = alloc_register();
            vis.lvalue = reg;
            emit(vis.rvalue + " " + reg);
        }
        return lvalue;
    }

    Visit make_visit(std::string const &lvalue, std::string const &rvalue) {
        return {lvalue, rvalue};
    }

    Visit visit(AST *ast) {
        if (ast->token.type == Token::Type::op) {
            auto res = opchar_to_opcode(ast->token.ident);
            for (auto const &arg: ast->token.args) {
                auto vis = visit(arg);
                res += " " + lvalue(vis);
            }
            return make_visit("", res);
        } else if (ast->token.type == Token::Type::mem) {
            make_visit("@" + ast->token.ident, "");
        } else if (ast->token.type == Token::Type::reg) {
            make_visit("$" + ast->token.ident, "");
        }
    }

    std::string get_assembly() {
        return lines;
    }
};

std::string translate_program(AST *ast) {
    Translator t;
    t.visit(ast);
    return t.get_assembly();
}

Program compile_program(std::string const &code) {
    auto ast = parse_program(code);
    auto lines = translate_program(ast.get());
    return assemble_program(lines);
}
