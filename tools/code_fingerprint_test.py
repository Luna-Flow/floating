import tempfile
import unittest
from pathlib import Path

import code_fingerprint as cf

PKG = "_M0FP311Luna_2dFlow8floating3pkg"
TYPE_A = "_M0TP311Luna_2dFlow8floating3pkg1A"
TYPE_B = "_M0TP311Luna_2dFlow8floating3pkg1B"
TYPE_C = "_M0TP311Luna_2dFlow8floating3pkg1C"


def layout_table(entries: list[tuple[str, list[str]]]) -> str:
    """A layout table in the generated shape: (struct name, offsets of its references)."""
    words: list[str] = []
    for name, offsets in entries:
        words.append(f"sizeof(struct {name}) / 4")
        words.append(str(len(offsets)))
        words.extend(f"offsetof(struct {name}, {field}) / 4 * 2" for field in offsets)
    total = len(words)
    body = ",\n".join(words)
    return f"static uint32_t const moonbit_layout_table_data[{total}] =\n  {{\n{body}\n  }};\n"


def layout_starts(entries: list[tuple[str, list[str]]]) -> list[int]:
    starts, index = [], 0
    for _, offsets in entries:
        starts.append(index)
        index += 2 + len(offsets)
    return starts


def program_text(
    *,
    counter: int = 100,
    first_closure_body: str = "x + 1",
    second_closure_body: str = "x + 2",
    line: int = 10,
    extra: str = "",
    types: tuple[tuple[str, tuple[tuple[str, str], ...]], ...] = (
        (TYPE_A, (("$0", "struct X*"),)),
        (TYPE_B, (("$0", "int32_t"),)),
    ),
    alloc: tuple[str, ...] = (TYPE_A, TYPE_B),
    table_order: tuple[str, ...] | None = None,
    init_value: int = 5,
    hook: str = "",
) -> str:
    """A small generated-C-like program whose counters and layout indices can be varied."""
    n = counter
    out = ['#include "moonbit.h"', f"#define Alias {PKG}helper", ""]
    for name, fields in types:
        body = "".join(f"  {ctype} {field};\n" for field, ctype in fields)
        out += [f"struct {name};", f"struct {name} {{\n{body}}};", ""]
    layout_names = table_order or alloc
    shape = {name: [f for f, ctype in fields if "*" in ctype] for name, fields in types}
    entries = [(name, shape[name]) for name in layout_names]
    starts = dict(zip(layout_names, layout_starts(entries)))
    out += [
        f"static int32_t {PKG}helper(int32_t _M0L1xS{n});",
        f"static int32_t {PKG}helper(int32_t _M0L1xS{n}) {{",
        f'  #line {line} "/Users/someone/checkout/pkg.mbt"',
        f"  int32_t _tmp_{n + 1} = _M0L1xS{n} * 2;",
        f"  return _tmp_{n + 1};",
        "}",
        "",
        f"static int32_t {PKG}first(int32_t x) {{",
        f"  return {PKG}first{'C'}{n + 5}l{line}(x);",
        "}",
        f"static int32_t {PKG}firstC{n + 5}l{line}(int32_t x) {{",
        f"  return {first_closure_body};",
        "}",
        f"static int32_t {PKG}firstC{n + 6}l{line + 1}(int32_t x) {{",
        f"  return {second_closure_body};",
        "}",
        f"static int32_t {PKG}second(int32_t x) {{",
        f"  int32_t _M0L6sharedS{n + 9} = x;",
        f"  int32_t a = {PKG}firstC{n + 6}l{line + 1}(_M0L6sharedS{n + 9});",
        f"  int32_t b = {PKG}firstC{n + 5}l{line}(x);",
        "  return a + b;",
        "}",
        "",
        f"static int32_t {PKG}entry(int32_t x) {{",
        f"  int32_t y = Alias(x);",
        f"  int32_t z = {PKG}second(y);",
        f"  return {PKG}first(z);",
        "}",
        "",
    ]
    for name in alloc:
        out += [
            f"static struct {name}* {PKG}make{name[-1]}(void) {{",
            f"  struct {name}* r = (struct {name}*)moonbit_malloc(sizeof(struct {name}));",
            f"  Moonbit_object_header(r)->meta",
            f"  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, {starts[name]}, 0);",
            "  return r;",
            "}",
            "",
        ]
    out += [
        f"static int32_t {PKG}third(int32_t _M0L6sharedS{n + 9}) {{ return _M0L6sharedS{n + 9}; }}",
        f"static int32_t {PKG}limit;",
        f"static int32_t {PKG}reads(int32_t x) {{ return x + {PKG}limit; }}",
        f"static int32_t {PKG}dispatch(int32_t op) {{",
        f"  return {PKG}entry(op) + {PKG}unrelated(op) + {PKG}reads(op);",
        "}",
        "void moonbit_init() {",
        "  moonbit_layout_table = moonbit_layout_table_data;",
        f"  {PKG}limit = {init_value};",
        "}",
        "int main(int argc, char** argv) {",
        "  moonbit_init();",
        f"  return {PKG}dispatch(argc);",
        "}",
        hook,
    ]
    out.append(f"static int32_t {PKG}unrelated(int32_t x) {{ return x; }}")
    out.append(extra)
    out.append(layout_table(entries))
    return "\n".join(out)


def parse(text: str, layout: bool = True, forbidden_paths: tuple[str, ...] = ()) -> cf.Program:
    return cf.parse_program(text, layout=layout, forbidden_paths=forbidden_paths)


def find(program: cf.Program, suffix: str) -> str:
    name: str = next(n for n in program.definitions if n.endswith(suffix))
    return name


def entry_fp(program: cf.Program, suffix: str) -> str:
    """The fingerprint of an entry with the dispatcher cut, as a unit key uses it."""
    return cf.fingerprint(program, find(program, suffix), cut={find(program, "dispatch")})


class SplitTests(unittest.TestCase):
    def test_line_directives_are_deleted_with_their_continuations(self) -> None:
        lines = ["a", '  #line 3 "x"', "b", "#line 4 \\", "  continued", "c"]
        self.assertEqual(cf.drop_line_directives(lines), ["a", "b", "c"])

    def test_every_line_is_accounted_for(self) -> None:
        program = parse(program_text())
        self.assertEqual(program.account.unaccounted, 0)
        self.assertGreater(program.account.directives, 0)
        self.assertGreater(program.account.items, 0)

    def test_functions_data_structs_and_macros_are_items(self) -> None:
        text = "\n".join(
            [
                "#define M(x) ((x) + 1)",
                "struct S;",
                "struct S {\n  int a;\n};",
                "static int f(int x) {\n  if (x) {\n    return 1;\n  }\n  return 0;\n}",
                "static int g = 3;",
                "static struct {\n  int a;\n} const anon_7 =\n  {\n    1\n  };",
                "static int f(int x);",
            ]
        )
        items, residue, account = cf.split_items(text)
        self.assertEqual(len(items), 7)
        self.assertEqual(residue, "")
        self.assertEqual(items[0].macro, "M")
        self.assertEqual([i.is_function for i in items], [False, False, False, True, False, False, False])
        keys = [cf.item_key(i) for i in items]
        self.assertEqual(keys, ["M", "struct S", "struct S", "f", "g", "anon_7", "f"])
        self.assertEqual(account.unaccounted, 0)

    def test_braces_in_strings_comments_and_block_comments_do_not_count(self) -> None:
        text = "\n".join(
            [
                "/* top comment {",
                "   continues */",
                "static int f(void) {",
                '  const char *s = "}{";',
                "  /* } multi",
                "     line { */",
                "  char c = '}';",
                "  return 0; // }",
                "}",
                "static int g = 1;",
            ]
        )
        items, residue, account = cf.split_items(text)
        self.assertEqual([cf.item_key(i) for i in items], ["f", "g"])
        self.assertEqual(account.unaccounted, 0)
        self.assertEqual(account.residue, 2)

    def test_extern_c_braces_and_preprocessor_are_residue(self) -> None:
        text = '#ifdef __cplusplus\nextern "C" {\n#endif\nstatic int g = 1;\n#ifdef __cplusplus\n}\n#endif\n'
        items, residue, account = cf.split_items(text)
        self.assertEqual(len(items), 1)
        self.assertIn("#ifdef __cplusplus", residue)
        self.assertEqual(account.unaccounted, 0)

    def test_a_file_ending_inside_an_item_is_an_error(self) -> None:
        with self.assertRaises(cf.ParseError):
            cf.split_items("static int f(void) {\n  return 0;\n")


class NamingTests(unittest.TestCase):
    def key(self, text: str) -> str | None:
        items, _, _ = cf.split_items(text)
        result: str | None = cf.item_key(items[0])
        return result

    def test_declarator_names(self) -> None:
        self.assertEqual(self.key("static struct T* name(\n  int a\n) {\n  return 0;\n}"), "name")
        self.assertEqual(self.key("static struct T* name(int a);"), "name")
        self.assertEqual(self.key("static struct T name;"), "name")
        self.assertEqual(self.key("static struct { int a; } const lit_3 = { 1 };"), "lit_3")
        self.assertEqual(self.key("struct T {\n  int a;\n};"), "struct T")
        self.assertEqual(self.key("struct T;"), "struct T")

    def test_unnamable_items_go_to_the_residue_digest(self) -> None:
        program = parse("static int (*fp)(int) = 0;\nstatic int g = 1;")
        self.assertEqual(len(program.unnamed), 1)
        other = parse("static int (*fp)(int) = 1;\nstatic int g = 1;")
        self.assertNotEqual(program.residue_digest, other.residue_digest)


class NormalisationTests(unittest.TestCase):
    def test_locals_are_renamed_by_first_appearance(self) -> None:
        a = cf.rename_locals("int _M0L1xS5 = _tmp_7; _M0L1xS5 += _tmp_7;", frozenset())
        b = cf.rename_locals("int _M0L1xS99 = _tmp_3; _M0L1xS99 += _tmp_3;", frozenset())
        self.assertEqual(a, b)

    def test_a_different_use_pattern_is_not_equal(self) -> None:
        a = cf.rename_locals("_tmp_1 = _tmp_2;", frozenset())
        b = cf.rename_locals("_tmp_1 = _tmp_1;", frozenset())
        self.assertNotEqual(a, b)

    def test_a_defined_name_is_never_renamed(self) -> None:
        self.assertEqual(cf.rename_locals("_tmp_1 = 0;", frozenset({"_tmp_1"})), "_tmp_1 = 0;")

    def test_counters_lines_and_paths_do_not_change_a_key(self) -> None:
        a = parse(program_text(counter=100, line=10))
        b = parse(program_text(counter=70000, line=345))
        self.assertEqual(entry_fp(a, "entry"), entry_fp(b, "entry"))
        self.assertEqual(a.residue_digest, b.residue_digest)

    def test_two_closures_that_swap_bodies_are_seen(self) -> None:
        a = parse(program_text(first_closure_body="x + 1", second_closure_body="x + 2"))
        b = parse(program_text(first_closure_body="x + 2", second_closure_body="x + 1"))
        self.assertNotEqual(entry_fp(a, "second"), entry_fp(b, "second"))

    def test_a_body_change_in_a_closure_reaches_its_users_only(self) -> None:
        a = parse(program_text())
        b = parse(program_text(first_closure_body="x + 9"))
        self.assertNotEqual(entry_fp(a, "entry"), entry_fp(b, "entry"))
        self.assertEqual(entry_fp(a, "unrelated"), entry_fp(b, "unrelated"))

    def test_canonical_names_keep_the_reference_edges(self) -> None:
        program = parse(program_text())
        entry = next(n for n in program.definitions if n.endswith("entry"))
        reach = cf.reachable(program, entry)
        closures = [n for n in reach if "__canon__" in n]
        self.assertEqual(len(closures), 2)
        # the canonical names are identifiers, so a body that mentions one still refers to it
        for name in closures:
            self.assertRegex(name, r"^[A-Za-z0-9_$]+$")

    def test_canonical_name_clash_is_an_error(self) -> None:
        clash = "q_N__canon__" + cf._short("a") + "__0"
        with self.assertRaises(cf.ParseError):
            cf.canonical_names({"a": "q_S1", "q_S1": "x", clash: "y"})


class ReferenceTests(unittest.TestCase):
    def test_calls_data_macros_and_types_are_references(self) -> None:
        program = parse(program_text())
        entry = next(n for n in program.definitions if n.endswith("entry"))
        reach = cf.reachable(program, entry)
        self.assertTrue(any(n.endswith("helper") for n in reach))  # through the macro Alias
        self.assertIn("Alias", reach)
        maker = next(n for n in program.definitions if n.endswith("makeA"))
        self.assertIn(f"struct {TYPE_A}", cf.reachable(program, maker))

    def test_an_unrelated_function_is_not_reachable(self) -> None:
        program = parse(program_text())
        entry = next(n for n in program.definitions if n.endswith("entry"))
        self.assertFalse(any(n.endswith("unrelated") for n in cf.reachable(program, entry)))

    def test_adding_an_unrelated_function_changes_no_key(self) -> None:
        a = parse(program_text())
        b = parse(program_text(extra=f"static int32_t {PKG}added(int32_t x) {{ return x; }}"))
        self.assertEqual(entry_fp(a, "entry"), entry_fp(b, "entry"))
        self.assertEqual(entry_fp(a, "makeA"), entry_fp(b, "makeA"))

    def test_a_residue_change_changes_every_key(self) -> None:
        a = parse(program_text())
        b = parse(program_text().replace('#include "moonbit.h"', '#include "moonbit.h"\n#pragma once'))
        self.assertNotEqual(entry_fp(a, "unrelated"), entry_fp(b, "unrelated"))

class LayoutTests(unittest.TestCase):
    def test_table_shape_is_decoded(self) -> None:
        entries = [(TYPE_A, ["$0", "$1"]), (TYPE_B, [])]
        decoded = cf.parse_layout_table(layout_table(entries))
        assert decoded is not None
        self.assertEqual(sorted(decoded), [0, 4])
        self.assertIn(f"offsetof(struct {TYPE_A}, $1) / 4 * 2", decoded[0])

    def test_a_table_of_another_shape_is_not_decoded(self) -> None:
        self.assertIsNone(cf.parse_layout_table("static uint32_t const moonbit_layout_table_data[2] = { 1, x };"))
        self.assertIsNone(cf.parse_layout_table("static uint32_t const moonbit_layout_table_data[3] = { 1, 5, 2 };"))
        self.assertIsNone(cf.parse_layout_table("static uint32_t const moonbit_layout_table_data[4] = { 1, 1, 2 };"))
        self.assertIsNone(cf.parse_layout_table("nothing"))

    def test_rewriting_counts_rewritten_and_fallbacks(self) -> None:
        text = "Moonbit_make_regular_object_header(CLASS, 0, 0); Moonbit_make_regular_object_header(CLASS, 1, 0); Moonbit_make_regular_object_header(CLASS, x, 0);"
        new, done, missed = cf.rewrite_layout_indices(text, {0: "LAYOUT{a}"})
        self.assertEqual((done, missed), (1, 2))
        self.assertIn("CLASS, LAYOUT{a}, 0", new)
        self.assertIn("CLASS, 1, 0", new)

    def test_the_program_reports_rewrites_and_no_fallbacks(self) -> None:
        program = parse(program_text())
        self.assertEqual(program.layout_rewritten, 2)
        self.assertEqual(program.layout_fallbacks, 0)

    def test_an_index_off_an_entry_boundary_stays_raw_and_is_counted(self) -> None:
        text = program_text().replace("INDEXED, 0, 0", "INDEXED, 1, 0")
        program = parse(text)
        self.assertEqual(program.layout_fallbacks, 1)
        self.assertEqual(program.layout_fallback_definitions, 1)

    def test_a_new_unrelated_type_shifts_indices_but_changes_no_other_key(self) -> None:
        base = program_text(alloc=(TYPE_A, TYPE_B))
        shifted = program_text(
            types=(
                (TYPE_C, (("$0", "struct X*"), ("$1", "struct X*"))),
                (TYPE_A, (("$0", "struct X*"),)),
                (TYPE_B, (("$0", "int32_t"),)),
            ),
            alloc=(TYPE_C, TYPE_A, TYPE_B),
        )
        a, b = parse(base), parse(shifted)
        for suffix in ("makeA", "makeB", "entry"):
            self.assertEqual(entry_fp(a, suffix), entry_fp(b, suffix), suffix)
        raw_a, raw_b = parse(base, layout=False), parse(shifted, layout=False)
        self.assertNotEqual(entry_fp(raw_a, "makeA"), entry_fp(raw_b, "makeA"))

    def test_reordering_two_types_changes_no_key(self) -> None:
        a = parse(program_text(alloc=(TYPE_A, TYPE_B)))
        b = parse(program_text(alloc=(TYPE_A, TYPE_B), table_order=(TYPE_B, TYPE_A)))
        for suffix in ("makeA", "makeB"):
            self.assertEqual(entry_fp(a, suffix), entry_fp(b, suffix), suffix)

    def test_a_field_changed_from_pointer_to_scalar_changes_its_allocators(self) -> None:
        a = parse(program_text())
        b = parse(
            program_text(
                types=(
                    (TYPE_A, (("$0", "int32_t"),)),
                    (TYPE_B, (("$0", "int32_t"),)),
                )
            )
        )
        self.assertNotEqual(entry_fp(a, "makeA"), entry_fp(b, "makeA"))
        self.assertEqual(entry_fp(a, "makeB"), entry_fp(b, "makeB"))

    def test_a_field_changed_between_two_pointer_fields_changes_its_allocators(self) -> None:
        a = parse(program_text(types=((TYPE_A, (("$0", "struct X*"), ("$1", "int32_t"))), (TYPE_B, (("$0", "int32_t"),)))))
        b = parse(program_text(types=((TYPE_A, (("$0", "int32_t"), ("$1", "struct X*"))), (TYPE_B, (("$0", "int32_t"),)))))
        self.assertNotEqual(entry_fp(a, "makeA"), entry_fp(b, "makeA"))

    def test_the_flag_names_the_normalisation_set(self) -> None:
        on, off = parse(program_text()), parse(program_text(), layout=False)
        self.assertIn("layout-index", on.version)
        self.assertNotIn("layout-index", off.version)
        self.assertNotEqual(entry_fp(on, "entry"), entry_fp(off, "entry"))


class StartUpTests(unittest.TestCase):
    """A: code that runs in the process without being reachable from the entry."""

    def test_a_changed_initialiser_changes_the_key_of_the_unit_that_reads_the_global(self) -> None:
        a, b = parse(program_text(init_value=5)), parse(program_text(init_value=6))
        reads = find(a, "reads")
        self.assertEqual(a.definitions[reads].digest, b.definitions[reads].digest)  # the reader itself is unchanged
        self.assertNotEqual(entry_fp(a, "reads"), entry_fp(b, "reads"))

    def test_the_start_up_closure_is_part_of_every_key(self) -> None:
        a, b = parse(program_text(init_value=5)), parse(program_text(init_value=6))
        for suffix in ("entry", "unrelated", "makeA"):
            self.assertNotEqual(entry_fp(a, suffix), entry_fp(b, suffix), suffix)

    def test_without_the_start_up_roots_the_hole_is_visible(self) -> None:
        a, b = parse(program_text(init_value=5)), parse(program_text(init_value=6))
        name = find(a, "reads")
        self.assertEqual(cf.fingerprint(a, name, startup=False), cf.fingerprint(b, name, startup=False))

    def test_the_cut_dispatcher_is_covered_by_its_own_text_only(self) -> None:
        a = parse(program_text())
        dispatch = find(a, "dispatch")
        cut = {dispatch}
        self.assertIn(dispatch, cf.reachable(a, list(cf.START_UP), cut))
        self.assertFalse(any(n.endswith("unrelated") for n in cf.reachable(a, list(cf.START_UP), cut)))
        self.assertTrue(any(n.endswith("unrelated") for n in cf.reachable(a, list(cf.START_UP))))

    def test_a_changed_dispatcher_changes_every_key(self) -> None:
        a = parse(program_text())
        b = parse(program_text().replace(f"{PKG}entry(op) + {PKG}unrelated(op)", f"{PKG}unrelated(op) + {PKG}entry(op)"))
        self.assertNotEqual(entry_fp(a, "makeA"), entry_fp(b, "makeA"))

    def test_the_layout_table_is_not_in_the_closure_when_headers_carry_their_entries(self) -> None:
        a = parse(program_text())
        entry = [*cf.START_UP, find(a, "entry")]
        self.assertNotIn("moonbit_layout_table_data", cf.reachable(a, entry, {find(a, "dispatch")}))
        raw = parse(program_text(), layout=False)
        self.assertIn("moonbit_layout_table_data", cf.reachable(raw, entry, {find(raw, "dispatch")}))

    def test_constructors_destructors_and_exit_hooks_are_refused(self) -> None:
        for hook in ("static void f(void) __attribute__((constructor));", "static int g = atexit(0);", "static int h = on_exit(0, 0);"):
            with self.assertRaises(cf.ParseError, msg=hook):
                parse(program_text(hook=hook))


class EntryTests(unittest.TestCase):
    """B: an entry that is not a definition is an error, never a constant key."""

    def test_unknown_entries_raise(self) -> None:
        program = parse(program_text())
        with self.assertRaises(cf.UnknownEntryError):
            cf.reachable(program, "absent")
        with self.assertRaises(cf.UnknownEntryError):
            cf.fingerprint(program, "absent")
        with self.assertRaises(cf.UnknownEntryError):
            cf.fingerprint(program, [find(program, "entry"), "absent"])

    def test_a_program_without_start_up_roots_raises(self) -> None:
        program = parse("static int f(void) { return 0; }\n")
        with self.assertRaises(cf.UnknownEntryError):
            cf.fingerprint(program, "f")
        self.assertTrue(cf.fingerprint(program, "f", startup=False))


class LocalNameTests(unittest.TestCase):
    """C: a name is renamed as a local only if it is local."""

    def test_names_shared_by_a_parent_and_its_closure_are_renamed_jointly(self) -> None:
        a, b = parse(program_text(counter=100)), parse(program_text(counter=9000))
        self.assertGreater(a.shared_locals, 0)
        self.assertEqual(a.nonlocal_names, [])
        self.assertEqual(entry_fp(a, "second"), entry_fp(b, "second"))

    def test_a_name_that_also_occurs_in_the_residue_is_left_as_it_is_and_counted(self) -> None:
        text = "#pragma mark _tmp_5\nstatic int f(void) {\n  int _tmp_5 = 1;\n  return _tmp_5;\n}\n"
        a = parse(text, forbidden_paths=())
        self.assertEqual(a.nonlocal_names, ["_tmp_5"])
        b = parse(text.replace("_tmp_5", "_tmp_6"))
        self.assertNotEqual(a.definitions["f"].digest, b.definitions["f"].digest)

    def test_joint_renaming_keeps_apart_names_of_different_groups(self) -> None:
        one = "static int f(void) {\n  return _M0L1xS1 + _M0L1yS2;\n}\nstatic int g(void) {\n  return _M0L1xS1;\n}\n"
        two = "static int f(void) {\n  return _M0L1xS1 + _M0L1yS2;\n}\nstatic int g(void) {\n  return _M0L1yS2;\n}\n"
        # g alone is the same text in both; f, which holds both names, differs
        self.assertEqual(parse(one).definitions["g"].digest, parse(two).definitions["g"].digest)
        self.assertNotEqual(parse(one).definitions["f"].digest, parse(two).definitions["f"].digest)

    def test_two_items_that_differ_only_in_a_local_name_with_a_second_counter_are_equal(self) -> None:
        a = "static int f(void) {\n  int _M0L10_2ax__4387S12 = 1;\n  return _M0L10_2ax__4387S12;\n}\n"
        b = a.replace("4387S12", "4388S99")
        self.assertEqual(parse(a).definitions["f"].digest, parse(b).definitions["f"].digest)
        c = a.replace("int _M0L10_2ax__4387S12 = 1;", "int _M0L10_2ax__4387S12 = 2;")
        self.assertNotEqual(parse(a).definitions["f"].digest, parse(c).definitions["f"].digest)

    def test_a_name_shared_by_a_parent_and_a_closure_ignores_its_spelling(self) -> None:
        one = "static int f(void) {\n  return _M0L2ayS5;\n}\nstatic int g(void) {\n  return _M0L2ayS5;\n}\n"
        two = one.replace("_M0L2ayS5", "_M0L4zz__77S9")
        self.assertEqual(parse(one).definitions["f"].digest, parse(two).definitions["f"].digest)
        self.assertEqual(parse(one).definitions["g"].digest, parse(two).definitions["g"].digest)


class InjectivityTests(unittest.TestCase):
    """D: the canonical renaming is checked injective."""

    def test_the_renaming_of_the_fixture_is_injective(self) -> None:
        names = cf.canonical_names({"a": "fC1l1", "b": "fC2l2", "fC1l1": "x", "fC2l2": "y"})
        self.assertEqual(len(set(names.values())), 2)

    def test_a_collision_of_owners_is_an_error(self) -> None:
        from unittest import mock

        with mock.patch.object(cf, "_short", return_value="same"):
            with self.assertRaises(cf.ParseError):
                cf.canonical_names({"a": "fC1l1", "b": "fC2l2", "fC1l1": "x", "fC2l2": "y"})


class LiteralTests(unittest.TestCase):
    """E: literals and comments are not code."""

    def test_the_scans_skip_literals_and_comments(self) -> None:
        code = 'x = _tmp_7 + f(y); s = "_tmp_7 f"; c = \'f\'; // f _tmp_7\n/* f\n _tmp_7 */'
        self.assertEqual(cf.identifiers(code), {"x", "_tmp_7", "f", "y", "s", "c"})
        renamed = cf.rename_locals(code, frozenset())
        self.assertIn('"_tmp_7 f"', renamed)
        self.assertIn("// f _tmp_7", renamed)
        self.assertIn("/* f\n _tmp_7 */", renamed)
        self.assertNotIn("x = _tmp_7", renamed)
        self.assertEqual(cf.apply_names('f(); "f"; // f', {"f": "g"}), 'g(); "f"; // f')

    def test_a_name_inside_a_string_is_not_a_reference_but_is_hashed(self) -> None:
        base = program_text(extra=f'static const char *p = "{PKG}unrelated";')
        program = parse(base)
        p = find(program, "p") if False else next(n for n in program.definitions if n == "p")
        self.assertNotIn(find(program, "unrelated"), program.definitions[p].refs)
        other = parse(base.replace(f'"{PKG}unrelated"', f'"{PKG}different"'))
        self.assertNotEqual(program.definitions[p].digest, other.definitions[p].digest)


class TokenPastingTests(unittest.TestCase):
    """F: a reference built by `##` is invisible to the scan."""

    def test_token_pasting_in_the_generated_c_is_refused(self) -> None:
        text = program_text(extra="#define JOIN(a) a##_x")
        with self.assertRaises(cf.ParseError):
            parse(text)
        self.assertGreater(len(cf.parse_program(text, allow_token_pasting=True).definitions), 0)


class CompileCommandTests(unittest.TestCase):
    """G and H: the compiler command lines and the stub coverage."""

    DRY = "\n".join(
        [
            "moonc build-package ./library/src/a.mbt -o /tgt/native/a.core",
            "/usr/bin/cc -o /tgt/native/release/build/k.o '-I$MOON_HOME/include' -c -fwrapv -O2 ./library/src/k/stub.c",
            "/usr/bin/cc -o /tgt/native/release/build/f.o -c -O2 ./.mooncakes/dep/fs/fs_native.c",
            "/usr/bin/cc -o /tgt/native/release/build/cli.o -c -O2 /tgt/native/release/build/cli.c",
        ]
    )

    def test_moonc_lines_are_dropped_and_paths_made_relative(self) -> None:
        commands = cf.compile_commands(self.DRY, Path("/tgt"), Path("/repo"))
        self.assertNotIn("moonc build-package", commands)
        self.assertNotIn("/tgt", commands)
        self.assertIn("<target>/native/release/build/cli.o", commands)
        self.assertIn("-fwrapv -O2", commands)

    def test_compiled_sources_inside_the_checkout_must_be_hashed(self) -> None:
        commands = cf.compile_commands(self.DRY, Path("/tgt"), Path("/repo"))
        self.assertEqual(cf.unhashed_sources(commands, {"library/src/k/stub.c", ".mooncakes/dep/fs/fs_native.c"}), [])
        self.assertEqual(cf.unhashed_sources(commands, {"library/src/k/stub.c"}), [".mooncakes/dep/fs/fs_native.c"])

    def test_moon_build_commands_uses_the_dry_run_and_none_when_it_prints_nothing(self) -> None:
        seen: list[list[str]] = []

        def run(command: list[str], cwd: Path | None = None) -> str:
            seen.append(command)
            return self.DRY

        commands = cf.moon_build_commands(Path("/repo"), Path("/tgt"), run)
        assert commands is not None
        self.assertIn("--dry-run", seen[0])
        self.assertIn("--release", seen[0])
        self.assertIsNone(cf.moon_build_commands(Path("/repo"), Path("/tgt"), lambda command, cwd=None: ""))

    def test_problems_name_missing_commands_unhashed_sources_and_pastes(self) -> None:
        self.assertEqual(cf.toolchain_problems({"compile-commands": "x"}), [])
        self.assertEqual(len(cf.toolchain_problems({})), 1)
        self.assertEqual(len(cf.toolchain_problems({"compile-commands": "x", "unhashed-sources": "a.c"})), 1)
        self.assertEqual(len(cf.toolchain_problems({"compile-commands": "x", "token-pasting-headers": "2"})), 1)


class CounterFamilyTests(unittest.TestCase):
    """Compiler counters inside names: generic instances, loop labels, `|` closures."""

    def test_the_pipe_closure_counter_is_anchored_at_the_end_of_the_name(self) -> None:
        # a hexadecimal run that starts with `7c` after an underscore is not a counter
        self.assertEqual(cf.counter_stem("x__canon__7c8b1234__0"), "x__canon__7c8b1234__0")
        self.assertEqual(cf.counter_stem("f_2efinalize_7c25726"), "f_2efinalize_7cN")
        self.assertEqual(cf.counter_stem("f_2efinalize_7c25726$object"), "f_2efinalize_7cN$object")

    def test_the_stem_of_each_family_drops_its_counter(self) -> None:
        self.assertEqual(cf.counter_stem("_M0MPB4Iter4nextN6constrS1771GcE"), "_M0MPB4Iter4nextN6constrNGcE")
        self.assertEqual(cf.counter_stem("_M0FPB20fixed__choose__pivotN7sort__3S4066GsE"), "_M0FPB20fixed__choose__pivotN7sort__3NGsE")
        self.assertEqual(cf.counter_stem("fdecimal_2eDecimal_3a_3atry__ctx_2efinalize_7c25726"), "fdecimal_2eDecimal_3a_3atry__ctx_2efinalize_7cN")
        self.assertEqual(cf.counter_stem("pN6constrS12"), "pN6constrN")
        self.assertEqual(cf.counter_stem("plain__name"), "plain__name")

    def test_two_builds_that_differ_only_in_such_counters_are_equal(self) -> None:
        def text(a: int, b: int, c: int) -> str:
            return "\n".join(
                [
                    f"static int32_t Iter4nextN6constrS{a}GcE = 1;",
                    f"static int32_t f_2efinalize_7c{b}(void) {{ return 2; }}",
                    f"static int32_t sortN7sort__3S{c}GsE = 3;",
                    f"static int32_t user(void) {{ return Iter4nextN6constrS{a}GcE + f_2efinalize_7c{b}() + sortN7sort__3S{c}GsE; }}",
                    "",
                ]
            )

        one, two = parse(text(10, 20, 30)), parse(text(7, 99, 4))
        self.assertEqual(one.definitions["user"].digest, two.definitions["user"].digest)
        self.assertEqual(set(one.definitions), set(two.definitions))
        self.assertEqual(cf.fingerprint(one, "user", startup=False), cf.fingerprint(two, "user", startup=False))

    def test_a_real_difference_in_such_a_definition_is_still_seen(self) -> None:
        a = "static int32_t gN6constrS5GcE = 1;\nstatic int32_t user(void) { return gN6constrS5GcE; }\n"
        b = a.replace("= 1;", "= 2;")
        self.assertNotEqual(cf.fingerprint(parse(a), "user", startup=False), cf.fingerprint(parse(b), "user", startup=False))

    def test_two_names_of_one_stem_in_one_build_stay_distinct(self) -> None:
        text = "\n".join(
            [
                "static int32_t gN6constrS5GcE = 1;",
                "static int32_t gN6constrS6GcE = 2;",
                "static int32_t user(void) { return gN6constrS5GcE + gN6constrS6GcE; }",
                "",
            ]
        )
        program = parse(text)
        self.assertEqual(len([n for n in program.definitions if "__canon__" in n]), 2)
        swapped = parse(text.replace("= 1;", "= TMP;").replace("= 2;", "= 1;").replace("= TMP;", "= 2;"))
        self.assertNotEqual(cf.fingerprint(program, "user", startup=False), cf.fingerprint(swapped, "user", startup=False))

    def test_loop_labels_are_locals_renamed_by_position(self) -> None:
        a = "static int f(void) {\n  _2awhile_3024:;\n  goto _2awhile_3024;\n  _2afor_5:;\n  goto _2afor_5;\n}\n"
        b = a.replace("_2awhile_3024", "_2awhile_3022").replace("_2afor_5", "_2afor_9")
        self.assertEqual(parse(a).definitions["f"].digest, parse(b).definitions["f"].digest)
        c = a.replace("goto _2afor_5;", "goto _2awhile_3024;")
        self.assertNotEqual(parse(a).definitions["f"].digest, parse(c).definitions["f"].digest)
        self.assertEqual(cf.local_kind("_2awhile_3024"), "loop-label")


class ForbiddenPathTests(unittest.TestCase):
    def test_a_path_in_line_directives_is_fine_elsewhere_it_is_counted(self) -> None:
        clean = parse(program_text(), forbidden_paths=("/Users/someone/checkout",))
        self.assertEqual(clean.path_hits, 0)
        dirty = parse(program_text(extra='static const char *p = "/Users/someone/checkout/x";'), forbidden_paths=("/Users/someone/checkout",))
        self.assertEqual(dirty.path_hits, 1)


class ToolchainTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.home = root / "moon"
        (self.repo / "library/src/k").mkdir(parents=True)
        (self.repo / "tooling").mkdir()
        (self.home / "lib/runtime").mkdir(parents=True)
        (self.home / "include").mkdir()
        (self.repo / "library/src/k/stub.c").write_text('int x = getenv("LUNA_MODE") != 0;\n')
        (self.repo / "library/src/k/moon.pkg").write_text('options("native-stub": ["stub.c"])\n')
        (self.repo / "library/src/k/plain.pkg").write_text("x")
        (self.home / "lib/runtime/runtime.c").write_text("runtime\n")
        (self.home / "include/moonbit.h").write_text("header\n")
        (self.repo / ".mooncakes/dep/fs").mkdir(parents=True)
        (self.repo / ".mooncakes/dep/fs/fs_native.c").write_text("int fs;\n")

    def collect(self, stage_env: dict[str, str] | None = None) -> dict[str, str]:
        def run(command: list[str]) -> str:
            return "v1" if command[0] == "moon" else "other"

        return cf.collect_toolchain(self.repo, self.home, run, stage_env=stage_env, environ={})

    def test_digest_is_stable_and_depends_on_every_part(self) -> None:
        parts = self.collect()
        self.assertEqual(cf.toolchain_digest(parts), cf.toolchain_digest(dict(parts)))
        for name in list(parts):
            changed = dict(parts)
            changed[name] = changed[name] + "x"
            self.assertNotEqual(cf.toolchain_digest(parts), cf.toolchain_digest(changed), name)

    def test_each_input_changes_the_digest(self) -> None:
        base = cf.toolchain_digest(self.collect())
        (self.home / "lib/runtime/runtime.c").write_text("runtime changed\n")
        self.assertNotEqual(base, cf.toolchain_digest(self.collect()))
        (self.home / "lib/runtime/runtime.c").write_text("runtime\n")
        (self.repo / "library/src/k/stub.c").write_text('int x = getenv("LUNA_MODE") != 1;\n')
        self.assertNotEqual(base, cf.toolchain_digest(self.collect()))
        (self.repo / "library/src/k/stub.c").write_text('int x = getenv("LUNA_MODE") != 0;\n')
        (self.repo / "library/src/k/moon.pkg").write_text('options("native-stub": ["stub.c"], "cc-flags": "-O3")\n')
        self.assertNotEqual(base, cf.toolchain_digest(self.collect()))

    def test_environment_read_by_the_stubs_and_set_by_a_stage_is_in_the_key(self) -> None:
        base = cf.toolchain_digest(self.collect())
        self.assertNotEqual(base, cf.toolchain_digest(self.collect(stage_env={"LUNA_MODE": "c"})))
        self.assertNotEqual(base, cf.toolchain_digest(self.collect(stage_env={"OTHER": "1"})))
        parts = self.collect()
        self.assertEqual(parts["env:LUNA_MODE"], "<unset>")

    def test_the_stubs_of_dependencies_are_hashed_and_counted_per_root(self) -> None:
        base = self.collect()
        self.assertEqual(base["stub-files:.mooncakes"], "1")
        self.assertEqual(base["stub-files:library"], "1")
        self.assertEqual(base["stub-files:tooling"], "0")
        (self.repo / ".mooncakes/dep/fs/fs_native.c").write_text("int fs = 1;\n")
        self.assertNotEqual(cf.toolchain_digest(base), cf.toolchain_digest(self.collect()))

    def test_commands_and_pastes_reach_the_parts(self) -> None:
        commands = "/usr/bin/cc -c ./library/src/k/stub.c\n/usr/bin/cc -c ./.mooncakes/dep/fs/fs_native.c\n/usr/bin/cc -c ./.mooncakes/dep/missing.c"
        parts = cf.collect_toolchain(self.repo, self.home, lambda c: "v", environ={}, build_commands=commands)
        self.assertEqual(parts["unhashed-sources"], ".mooncakes/dep/missing.c")
        self.assertEqual(len(cf.toolchain_problems(parts)), 1)
        (self.home / "include/moonbit.h").write_text("#define J(a) a##b\n")
        pasted = cf.collect_toolchain(self.repo, self.home, lambda c: "v", environ={}, build_commands="x")
        self.assertEqual(pasted["token-pasting-headers"], "1")
        self.assertTrue(cf.toolchain_problems(pasted))
        self.assertTrue(cf.toolchain_problems(self.collect()))  # no commands given: not collected
        (self.home / "include/moonbit.h").write_text("header\n")
        (self.repo / ".mooncakes/dep/other.c").write_text("#define J(a) a##b\n")
        not_compiled = cf.collect_toolchain(self.repo, self.home, lambda c: "v", environ={}, build_commands=commands)
        self.assertEqual(not_compiled["token-pasting-headers"], "0")  # hashed, but not compiled
        (self.repo / ".mooncakes/dep/fs/fs_native.c").write_text("#define J(a) a##b\n")
        compiled = cf.collect_toolchain(self.repo, self.home, lambda c: "v", environ={}, build_commands=commands)
        self.assertEqual(compiled["token-pasting-headers"], "1")

    def test_a_renamed_local_that_also_occurs_in_a_header_or_stub_is_reported(self) -> None:
        program = parse("static int f(void) {\n  int _tmp_7 = 1;\n  return _tmp_7;\n}\n")
        self.assertEqual(program.renamed_locals, frozenset({"_tmp_7"}))
        self.assertEqual(cf.local_name_overlap(program, self.repo, self.home), [])
        (self.home / "include/moonbit.h").write_text("int _tmp_7;\n")
        self.assertEqual(cf.local_name_overlap(program, self.repo, self.home), ["_tmp_7"])
        (self.home / "include/moonbit.h").write_text("header\n")
        (self.repo / "library/src/k/stub.c").write_text("int _tmp_7;\n")
        self.assertEqual(cf.local_name_overlap(program, self.repo, self.home), ["_tmp_7"])

    def test_getenv_names_are_found(self) -> None:
        self.assertEqual(cf.env_names_read(['getenv("A_B")', 'x = getenv( "C" );']), ["A_B", "C"])


if __name__ == "__main__":
    unittest.main()
