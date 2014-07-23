/*
 *  yosys -- Yosys Open SYnthesis Suite
 *
 *  Copyright (C) 2012  Clifford Wolf <clifford@clifford.at>
 *  
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *  
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *  ---
 *
 *  A very simple and straightforward frontend for the RTLIL text
 *  representation (as generated by the 'ilang' backend).
 *
 */

%{
#include <list>
#include "ilang_frontend.h"
namespace ILANG_FRONTEND {
	RTLIL::Design *current_design;
	RTLIL::Module *current_module;
	RTLIL::Wire *current_wire;
	RTLIL::Memory *current_memory;
	RTLIL::Cell *current_cell;
	RTLIL::Process *current_process;
	std::vector<std::vector<RTLIL::SwitchRule*>*> switch_stack;
	std::vector<RTLIL::CaseRule*> case_stack;
	std::map<RTLIL::IdString, RTLIL::Const> attrbuf;
}
using namespace ILANG_FRONTEND;
%}

%name-prefix "rtlil_frontend_ilang_yy"

%union {
	char *string;
	int integer;
	RTLIL::Const *data;
	RTLIL::SigSpec *sigspec;
}

%token <string> TOK_ID TOK_VALUE TOK_STRING
%token <integer> TOK_INT
%token TOK_AUTOIDX TOK_MODULE TOK_WIRE TOK_WIDTH TOK_INPUT TOK_OUTPUT TOK_INOUT
%token TOK_CELL TOK_CONNECT TOK_SWITCH TOK_CASE TOK_ASSIGN TOK_SYNC
%token TOK_LOW TOK_HIGH TOK_POSEDGE TOK_NEGEDGE TOK_EDGE TOK_ALWAYS TOK_INIT
%token TOK_UPDATE TOK_PROCESS TOK_END TOK_INVALID TOK_EOL TOK_OFFSET
%token TOK_PARAMETER TOK_ATTRIBUTE TOK_MEMORY TOK_SIZE TOK_SIGNED

%type <sigspec> sigspec sigspec_list
%type <integer> sync_type
%type <data> constant

%expect 0
%debug

%%

input:
	optional_eol {
		attrbuf.clear();
	} design {
		if (attrbuf.size() != 0)
			rtlil_frontend_ilang_yyerror("dangling attribute");
	};

EOL:
	optional_eol TOK_EOL;

optional_eol:
	optional_eol TOK_EOL | /* empty */;

design:
	design module |
	design attr_stmt |
	design autoidx_stmt |
	/* empty */;

module:
	TOK_MODULE TOK_ID EOL {
		if (current_design->modules.count($2) != 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: redefinition of module %s.", $2).c_str());
		current_module = new RTLIL::Module;
		current_module->name = $2;
		current_module->attributes = attrbuf;
		current_design->modules[$2] = current_module;
		attrbuf.clear();
		free($2);
	} module_body TOK_END {
		if (attrbuf.size() != 0)
			rtlil_frontend_ilang_yyerror("dangling attribute");
	} EOL;

module_body:
	module_body module_stmt |
	/* empty */;

module_stmt:
	attr_stmt | wire_stmt | memory_stmt | cell_stmt | proc_stmt | conn_stmt;

attr_stmt:
	TOK_ATTRIBUTE TOK_ID constant EOL {
		attrbuf[$2] = *$3;
		delete $3;
		free($2);
	};

autoidx_stmt:
	TOK_AUTOIDX TOK_INT EOL {
		RTLIL::autoidx = std::max(RTLIL::autoidx, $2);
	};

wire_stmt:
	TOK_WIRE {
		current_wire = new RTLIL::Wire;
		current_wire->attributes = attrbuf;
		attrbuf.clear();
	} wire_options TOK_ID EOL {
		if (current_module->wires.count($4) != 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: redefinition of wire %s.", $4).c_str());
		current_wire->name = $4;
		current_module->wires[$4] = current_wire;
		free($4);
	};

wire_options:
	wire_options TOK_WIDTH TOK_INT {
		current_wire->width = $3;
	} |
	wire_options TOK_OFFSET TOK_INT {
		current_wire->start_offset = $3;
	} |
	wire_options TOK_INPUT TOK_INT {
		current_wire->port_id = $3;
		current_wire->port_input = true;
		current_wire->port_output = false;
	} |
	wire_options TOK_OUTPUT TOK_INT {
		current_wire->port_id = $3;
		current_wire->port_input = false;
		current_wire->port_output = true;
	} |
	wire_options TOK_INOUT TOK_INT {
		current_wire->port_id = $3;
		current_wire->port_input = true;
		current_wire->port_output = true;
	} |
	/* empty */;

memory_stmt:
	TOK_MEMORY {
		current_memory = new RTLIL::Memory;
		current_memory->attributes = attrbuf;
		attrbuf.clear();
	} memory_options TOK_ID EOL {
		if (current_module->memories.count($4) != 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: redefinition of memory %s.", $4).c_str());
		current_memory->name = $4;
		current_module->memories[$4] = current_memory;
		free($4);
	};

memory_options:
	memory_options TOK_WIDTH TOK_INT {
		current_memory->width = $3;
	} |
	memory_options TOK_SIZE TOK_INT {
		current_memory->size = $3;
	} |
	/* empty */;

cell_stmt:
	TOK_CELL TOK_ID TOK_ID EOL {
		if (current_module->cells.count($3) != 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: redefinition of cell %s.", $3).c_str());
		current_cell = new RTLIL::Cell;
		current_cell->type = $2;
		current_cell->name = $3;
		current_cell->attributes = attrbuf;
		current_module->cells[$3] = current_cell;
		attrbuf.clear();
		free($2);
		free($3);
	} cell_body TOK_END EOL;

cell_body:
	cell_body TOK_PARAMETER TOK_ID constant EOL {
		current_cell->parameters[$3] = *$4;
		free($3);
		delete $4;
	} |
	cell_body TOK_PARAMETER TOK_SIGNED TOK_ID constant EOL {
		current_cell->parameters[$4] = *$5;
		current_cell->parameters[$4].flags |= RTLIL::CONST_FLAG_SIGNED;
		free($4);
		delete $5;
	} |
	cell_body TOK_CONNECT TOK_ID sigspec EOL {
		if (current_cell->connections.count($3) != 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: redefinition of cell port %s.", $3).c_str());
		current_cell->connections[$3] = *$4;
		delete $4;
		free($3);
	} |
	/* empty */;

proc_stmt:
	TOK_PROCESS TOK_ID EOL {
		if (current_module->processes.count($2) != 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: redefinition of process %s.", $2).c_str());
		current_process = new RTLIL::Process;
		current_process->name = $2;
		current_process->attributes = attrbuf;
		current_module->processes[$2] = current_process;
		switch_stack.clear();
		switch_stack.push_back(&current_process->root_case.switches);
		case_stack.clear();
		case_stack.push_back(&current_process->root_case);
		attrbuf.clear();
		free($2);
	} case_body sync_list TOK_END EOL;

switch_stmt:
	attr_list TOK_SWITCH sigspec EOL {
		RTLIL::SwitchRule *rule = new RTLIL::SwitchRule;
		rule->signal = *$3;
		rule->attributes = attrbuf;
		switch_stack.back()->push_back(rule);
		attrbuf.clear();
		delete $3;
	} switch_body TOK_END EOL;

attr_list:
	/* empty */ |
	attr_list attr_stmt;

switch_body:
	switch_body TOK_CASE {
		RTLIL::CaseRule *rule = new RTLIL::CaseRule;
		switch_stack.back()->back()->cases.push_back(rule);
		switch_stack.push_back(&rule->switches);
		case_stack.push_back(rule);
	} compare_list EOL case_body {
		switch_stack.pop_back();
		case_stack.pop_back();
	} |
	/* empty */;

compare_list:
	sigspec {
		case_stack.back()->compare.push_back(*$1);
		delete $1;
	} |
	compare_list ',' sigspec {
		case_stack.back()->compare.push_back(*$3);
		delete $3;
	} |
	/* empty */;

case_body:
	switch_stmt case_body |
	assign_stmt case_body |
	/* empty */;

assign_stmt:
	TOK_ASSIGN sigspec sigspec EOL {
		case_stack.back()->actions.push_back(RTLIL::SigSig(*$2, *$3));
		delete $2;
		delete $3;
	};

sync_list:
	sync_list TOK_SYNC sync_type sigspec EOL {
		RTLIL::SyncRule *rule = new RTLIL::SyncRule;
		rule->type = RTLIL::SyncType($3);
		rule->signal = *$4;
		current_process->syncs.push_back(rule);
		delete $4;
	} update_list |
	sync_list TOK_SYNC TOK_ALWAYS EOL {
		RTLIL::SyncRule *rule = new RTLIL::SyncRule;
		rule->type = RTLIL::SyncType::STa;
		rule->signal = RTLIL::SigSpec();
		current_process->syncs.push_back(rule);
	} update_list |
	sync_list TOK_SYNC TOK_INIT EOL {
		RTLIL::SyncRule *rule = new RTLIL::SyncRule;
		rule->type = RTLIL::SyncType::STi;
		rule->signal = RTLIL::SigSpec();
		current_process->syncs.push_back(rule);
	} update_list |
	/* empty */;

sync_type:
	TOK_LOW { $$ = RTLIL::ST0; } |
	TOK_HIGH { $$ = RTLIL::ST1; } |
	TOK_POSEDGE { $$ = RTLIL::STp; } |
	TOK_NEGEDGE { $$ = RTLIL::STn; } |
	TOK_EDGE { $$ = RTLIL::STe; };

update_list:
	update_list TOK_UPDATE sigspec sigspec EOL {
		current_process->syncs.back()->actions.push_back(RTLIL::SigSig(*$3, *$4));
		delete $3;
		delete $4;
	} |
	/* empty */;

constant:
	TOK_VALUE {
		char *ep;
		int width = strtol($1, &ep, 10);
		std::list<RTLIL::State> bits;
		while (*(++ep) != 0) {
			RTLIL::State bit = RTLIL::Sx;
			switch (*ep) {
			case '0': bit = RTLIL::S0; break;
			case '1': bit = RTLIL::S1; break;
			case 'x': bit = RTLIL::Sx; break;
			case 'z': bit = RTLIL::Sz; break;
			case '-': bit = RTLIL::Sa; break;
			case 'm': bit = RTLIL::Sm; break;
			}
			bits.push_front(bit);
		}
		if (bits.size() == 0)
			bits.push_back(RTLIL::Sx);
		while ((int)bits.size() < width) {
			RTLIL::State bit = bits.back();
			if (bit == RTLIL::S1)
				bit = RTLIL::S0;
			bits.push_back(bit);
		}
		while ((int)bits.size() > width)
			bits.pop_back();
		$$ = new RTLIL::Const;
		for (auto it = bits.begin(); it != bits.end(); it++)
			$$->bits.push_back(*it);
		free($1);
	} |
	TOK_INT {
		$$ = new RTLIL::Const($1, 32);
	} |
	TOK_STRING {
		$$ = new RTLIL::Const($1);
		free($1);
	};

sigspec:
	constant {
		$$ = new RTLIL::SigSpec(*$1);
		delete $1;
	} |
	TOK_ID {
		if (current_module->wires.count($1) == 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: wire %s not found", $1).c_str());
		$$ = new RTLIL::SigSpec(current_module->wires[$1]);
		free($1);
	} |
	TOK_ID '[' TOK_INT ']' {
		if (current_module->wires.count($1) == 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: wire %s not found", $1).c_str());
		$$ = new RTLIL::SigSpec(RTLIL::SigSpec::grml(current_module->wires[$1], $3));
		free($1);
	} |
	TOK_ID '[' TOK_INT ':' TOK_INT ']' {
		if (current_module->wires.count($1) == 0)
			rtlil_frontend_ilang_yyerror(stringf("ilang error: wire %s not found", $1).c_str());
		$$ = new RTLIL::SigSpec(RTLIL::SigSpec::grml(current_module->wires[$1], $5, $3 - $5 + 1));
		free($1);
	} |
	'{' sigspec_list '}' {
		$$ = $2;
	};

sigspec_list:
	sigspec_list sigspec {
		$$ = new RTLIL::SigSpec;
		$$->append(*$2);
		$$->append(*$1);
		delete $1;
		delete $2;
	} |
	/* empty */ {
		$$ = new RTLIL::SigSpec;
	};

conn_stmt:
	TOK_CONNECT sigspec sigspec EOL {
		if (attrbuf.size() != 0)
			rtlil_frontend_ilang_yyerror("dangling attribute");
		current_module->connections.push_back(RTLIL::SigSig(*$2, *$3));
		delete $2;
		delete $3;
	};

