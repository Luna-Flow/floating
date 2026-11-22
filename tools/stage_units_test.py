import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import incremental as inc
import stage_units as su

L = su.L
SPEC_MOON = su.StageSpec("T: moon", "moon", (f"{L}/low",))
SPEC_PY = su.StageSpec("T: python", "python", declared=("tools/check.py", "data/"))
OK = (0, "Total tests: 7, passed: 7, failed: 0.\n")
VERSION = "3.13.0 (test build)"
START = f"B 4242 {VERSION}\n"  # the start line of the audit hook


class CoveredTest(unittest.TestCase):
    def test_files_directories_and_ignored_parts(self) -> None:
        declared = ("tools/a.py", "data/")
        self.assertTrue(su.covered("tools/a.py", declared))
        self.assertTrue(su.covered("data/x/y.itl", declared))
        self.assertTrue(su.covered("data", declared))  # the directory itself (a listing)
        # a path with a `.git` or `__pycache__` part is left out of the key of a declared directory, so a
        # directory never covers it; only a unit that declares that very file does
        self.assertFalse(su.covered("tools/__pycache__/a.cpython.pyc", declared))
        self.assertFalse(su.covered("data/__pycache__/state.json", declared))
        self.assertFalse(su.covered(".git/HEAD", declared))
        self.assertTrue(su.covered(".git/HEAD", (*declared, ".git/HEAD")))
        self.assertFalse(su.covered("tools/b.py", declared))
        self.assertFalse(su.covered("data2/x", declared))  # not a prefix match of the directory name
        self.assertFalse(su.covered("library/src/a.mbt", declared))

    def test_audit_parsing_and_the_undeclared_set(self) -> None:
        audit = su.parse_audit("R tools/a.py\nR data/x\nD data\nD library/src\nR tools/b.py\nS /bin/ls\nS /usr/bin/python3\n")
        self.assertEqual(su.undeclared(audit, ("tools/a.py", "data/")), ["library/src", "tools/b.py"])
        self.assertEqual(su.undeclared(su.parse_audit("D tools\nD .\nD testdata\n"), ("tools/a.py", "testdata/interval/")), [])  # listing above a declared entry
        self.assertEqual(su.unseen_programs(audit, sys.executable), ["/bin/ls"])


class KeyTest(unittest.TestCase):
    def key(self, spec: su.StageSpec, **change: str) -> str:
        unit = su.StageUnit(spec, ("cmd",))
        base = dict(content="c", modules="m", compile_commands="x", wrapper="w", hook="h", toolchain="t", verifier="v", python_version="3.13", ambient="")
        base.update(change)
        return su.key_parts(unit, **base)[0]

    def test_every_input_of_a_moon_unit_changes_its_key(self) -> None:
        reference = self.key(SPEC_MOON)
        for part, value in (("content", "c2"), ("modules", "m2"), ("compile_commands", "y"), ("wrapper", "w2"), ("hook", "h2"), ("toolchain", "t2"), ("verifier", "v2"), ("ambient", "MOON_X=1")):
            self.assertNotEqual(self.key(SPEC_MOON, **{part: value}), reference, part)
        self.assertEqual(self.key(SPEC_MOON, python_version="2"), reference)  # not an input of a moon stage; the hook directory is one of every unit

    def test_every_input_of_a_python_unit_changes_its_key(self) -> None:
        reference = self.key(SPEC_PY)
        for part, value in (("content", "c2"), ("hook", "h2"), ("python_version", "3.14"), ("toolchain", "t2"), ("verifier", "v2")):
            self.assertNotEqual(self.key(SPEC_PY, **{part: value}), reference, part)
        self.assertEqual(self.key(SPEC_PY, modules="m2", wrapper="w2", compile_commands="y"), reference)

    def test_the_declaration_and_the_command_are_in_the_key(self) -> None:
        other = su.StageSpec("T: python", "python", declared=("tools/check.py", "data/", "more/"))
        self.assertNotEqual(self.key(SPEC_PY), self.key(other))
        a = su.key_parts(su.StageUnit(SPEC_PY, ("a",)), "c", "m", "x", "w", "h", "t", "v", "p", "")[0]
        b = su.key_parts(su.StageUnit(SPEC_PY, ("b",)), "c", "m", "x", "w", "h", "t", "v", "p", "")[0]
        self.assertNotEqual(a, b)


class RealAuditHookTest(unittest.TestCase):
    """The hook itself, in a real interpreter: what a stage reads, lists and starts."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        (self.root / "tools/stage_audit").mkdir(parents=True)
        (self.root / "tools/stage_audit/sitecustomize.py").write_text((su.Path(__file__).parent / "stage_audit/sitecustomize.py").read_text())
        (self.root / "data").mkdir()
        (self.root / "library").mkdir()
        (self.root / "data/a.txt").write_text("a")
        (self.root / "other.txt").write_text("b")
        (self.root / "tools/check.py").write_text("")

    def run_script(self, body: str) -> su.Audit:
        script = self.root / "tools/check.py"
        script.write_text(body)
        log = self.root / "audit.log"
        env = su.audit_environment(self.root, log, os.environ)
        result = subprocess.run([sys.executable, str(script)], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return su.parse_audit(log.read_text() if log.exists() else "")

    def test_a_declared_read_is_inside_and_an_undeclared_one_is_found(self) -> None:
        audit = self.run_script("print(open('data/a.txt').read()); print(open('other.txt').read())")
        self.assertIn("data/a.txt", audit.reads)
        self.assertIn("other.txt", audit.reads)
        self.assertEqual(su.undeclared(audit, ("tools/check.py", "data/")), ["other.txt"])

    def test_a_listing_and_a_glob_of_an_undeclared_directory_are_found(self) -> None:
        audit = self.run_script("import os, glob; os.listdir('library'); glob.glob('other*.txt'); glob.glob('data/*.txt')")
        self.assertIn("library", audit.listings)
        self.assertEqual(su.undeclared(audit, ("tools/check.py", "data/")), ["library", "other*.txt"])

    def test_writes_are_not_reads_and_outside_the_root_is_ignored(self) -> None:
        audit = self.run_script("open('out.txt', 'w').write('x'); open('/etc/hosts').read()")
        self.assertNotIn("out.txt", audit.reads)
        self.assertEqual(su.undeclared(audit, ("tools/check.py", "data/")), [])

    def test_a_child_python_process_and_another_program_are_seen(self) -> None:
        audit = self.run_script(
            "import subprocess, sys\n"
            "subprocess.run([sys.executable, '-c', \"open('other.txt').read()\"])\n"
            "subprocess.run(['ls', '.'], capture_output=True)\n"
        )
        self.assertIn("other.txt", audit.reads)  # read by the child
        self.assertEqual([Path(p).name for p in su.unseen_programs(audit, sys.executable)], ["ls"])

    def test_the_hook_does_not_change_what_the_stage_prints(self) -> None:
        script = self.root / "tools/check.py"
        script.write_text("print(open('data/a.txt').read())")
        plain = subprocess.run([sys.executable, str(script)], cwd=self.root, capture_output=True, text=True).stdout
        env = su.audit_environment(self.root, self.root / "audit.log", os.environ)
        audited = subprocess.run([sys.executable, str(script)], cwd=self.root, env=env, capture_output=True, text=True).stdout
        self.assertEqual(plain, audited)

    def test_the_directory_of_the_hook_is_a_declared_read(self) -> None:
        # On CI the interpreter lists the hook directory again after the hook is installed (a module is
        # looked for with the finder caches dropped); forced here, so that it shows on every machine.
        audit = self.run_script("import importlib\nimportlib.invalidate_caches()\ntry:\n    import no_such_module_anywhere\nexcept ImportError:\n    pass\n")
        self.assertIn("tools/stage_audit", audit.listings)
        self.assertEqual(su.undeclared(audit, ("tools/check.py", "data/")), [])

    def test_the_hook_writes_a_start_line_and_an_interpreter_that_does_not_load_it_does_not(self) -> None:
        script = self.root / "tools/check.py"
        script.write_text("print(open('other.txt').read())")
        log = self.root / "audit.log"
        env = su.audit_environment(self.root, log, os.environ)
        for flags, started in (([], True), (["-I"], False), (["-S"], False)):
            log.write_text("")
            subprocess.run([sys.executable, *flags, str(script)], cwd=self.root, env=env, capture_output=True, text=True, check=True)
            audit = su.parse_audit(log.read_text())
            self.assertEqual(bool(audit.starts), started, flags)
            if started:
                self.assertEqual(audit.starts, (sys.version,))
            else:
                self.assertEqual(audit.reads, ())  # the read of other.txt was not seen, and an empty log must not read as clean
                self.assertIn("did not start", su.not_recorded_why(audit, sys.executable, sys.version))

    def test_a_read_outside_the_repository_counts_unless_it_is_the_interpreters_or_the_runs_own(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other).resolve() / "cache.txt"
            outside.write_text("x")
            made = Path(other).resolve() / "made.txt"
            audit = self.run_script(
                "import json, os\n"  # the standard library is the interpreter's own
                f"open({str(outside)!r}).read()\n"
                f"open({str(made)!r}, 'w').write('y')\n"
                f"open({str(made)!r}).read()\n"
                f"open({str(outside)!r}, 'w').write('z')\n"  # a write is not a read
            )
        self.assertEqual(self.mine(audit), [str(outside)])
        self.assertIn("outside the repository", su.not_recorded_why(audit, sys.executable, sys.version))
        self.assertEqual(su.undeclared(audit, ("tools/check.py", "data/")), [])  # not a file of the repository

    def test_a_file_created_by_one_process_of_the_run_and_read_by_another_is_the_runs_own(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            made = Path(other).resolve() / "made.txt"
            audit = self.run_script(
                "import subprocess, sys\n"
                f"open({str(made)!r}, 'w').write('y')\n"
                f"subprocess.run([sys.executable, '-c', \"open({str(made)!r}).read()\"], check=True)\n"
            )
        self.assertEqual(self.mine(audit), [])

    def test_a_compiled_module_of_the_tree_cannot_run_in_place_of_its_source(self) -> None:
        import importlib.util
        import py_compile

        helper = self.root / "tools/helper.py"
        helper.write_text("NAME = 'source'\n")
        decoy = self.root / "decoy.py"
        decoy.write_text("NAME = 'stale compiled module'\n")
        cached = Path(importlib.util.cache_from_source(str(helper)))
        cached.parent.mkdir(exist_ok=True)
        # a compiled module that is loaded without looking at its source: the key (the content of helper.py) does not cover it
        py_compile.compile(str(decoy), cfile=str(cached), doraise=True, invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)
        script = self.root / "tools/check.py"
        script.write_text("import sys\nsys.path.insert(0, 'tools')\nimport helper\nprint(helper.NAME)\n")
        log = self.root / "audit.log"
        with tempfile.TemporaryDirectory() as pycache:
            env = su.audit_environment(self.root, log, os.environ, Path(pycache))
            result = subprocess.run([sys.executable, str(script)], cwd=self.root, env=env, capture_output=True, text=True, check=True)
        audit = su.parse_audit(log.read_text())
        self.assertEqual(result.stdout.strip(), "source")
        self.assertIn("tools/helper.py", audit.reads)
        self.assertEqual(su.compiled_reads(audit), [])
        self.assertEqual(self.mine(audit), [])  # the private cache of the run is not an outside input
        self.assertEqual(su.undeclared(audit, ("tools/check.py", "tools/helper.py")), [])

    def python_children_are_counted(self, body: str) -> su.Audit:
        script = self.root / "tools/check.py"
        script.write_text(body)
        log = self.root / "audit.log"
        env = su.audit_environment(self.root, log, os.environ)
        subprocess.run([sys.executable, str(script)], cwd=self.root, env=env, capture_output=True, text=True, check=True)
        self.last_log = log.read_text()
        return su.parse_audit(self.last_log)

    @staticmethod
    def mine(audit: su.Audit) -> list[str]:
        """The outside reads of the script, without the directories of `sys.path` that some interpreters list on their own
        (an installed-packages directory is listed when a module is looked for there; that stays an outside input)."""
        import sysconfig

        search_path = {os.path.realpath(p) for p in sys.path if p}
        search_path |= {os.path.realpath(sysconfig.get_path(name)) for name in ("purelib", "platlib")}
        return [p for p in su.outside_reads(audit) if p not in search_path and os.path.basename(p) not in ("site-packages", "dist-packages")]

    def assert_counting_is_right(self, audit: su.Audit) -> None:
        why = su.not_recorded_why(audit, sys.executable, sys.version)
        self.assertNotIn("loaded the hook", why, self.last_log)
        self.assertNotIn("another version", why, self.last_log)

    def test_a_python_child_that_does_not_load_the_hook_is_not_recorded(self) -> None:
        read = "open('other.txt').read()"  # an in-repository file that no unit declares
        children = {
            "-I": f"subprocess.run([sys.executable, '-I', '-c', {read!r}], check=True)",
            "-E": f"subprocess.run([sys.executable, '-E', '-c', {read!r}], check=True)",
            "-S": f"subprocess.run([sys.executable, '-S', '-c', {read!r}], check=True)",
            "env={}": f"subprocess.run([sys.executable, '-c', {read!r}], env={{}}, check=True)",
            "no PYTHONPATH": f"subprocess.run([sys.executable, '-c', {read!r}], env={{k: v for k, v in os.environ.items() if k != 'PYTHONPATH'}}, check=True)",
            "os.execv": f"os.execv(sys.executable, [sys.executable, '-I', '-c', {read!r}])",
            "os.posix_spawn": f"os.waitpid(os.posix_spawn(sys.executable, [sys.executable, '-I', '-c', {read!r}], {{}}), 0)",
        }
        for name, launch in children.items():
            audit = self.python_children_are_counted(f"import os, subprocess, sys\n{launch}\n")
            self.assertNotIn("other.txt", audit.reads, name)  # the unhooked child's read is invisible
            self.assertIn("Python processes loaded the hook", su.not_recorded_why(audit, sys.executable, sys.version), name)

    def test_a_stale_compiled_module_loaded_by_an_unhooked_child_is_not_recorded(self) -> None:
        import importlib.util
        import py_compile

        helper = self.root / "tools/helper.py"
        helper.write_text("NAME = 'source'\n")
        decoy = self.root / "decoy.py"
        decoy.write_text("NAME = 'stale'\n")
        cached = Path(importlib.util.cache_from_source(str(helper)))
        cached.parent.mkdir(exist_ok=True)
        py_compile.compile(str(decoy), cfile=str(cached), doraise=True, invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)
        audit = self.python_children_are_counted(
            "import subprocess, sys\n"
            "subprocess.run([sys.executable, '-I', '-c', \"import sys; sys.path.insert(0, 'tools'); import helper; print(helper.NAME)\"], check=True)\n"
        )
        self.assertIn("Python processes loaded the hook", su.not_recorded_why(audit, sys.executable, sys.version))

    def test_hooked_python_children_are_counted_and_recorded(self) -> None:
        audit = self.python_children_are_counted(
            "import subprocess, sys\n"
            "subprocess.run([sys.executable, '-c', 'pass'], check=True)\n"
            "subprocess.run([sys.executable, '-c', 'import subprocess, sys; subprocess.run([sys.executable, \"-c\", \"pass\"])'], check=True)\n"
        )
        # the log is in the message: it shows which events one launch raised on the machine that runs this
        self.assertEqual((len(audit.starts), len(audit.launches)), (4, 3), f"python {sys.version.split()[0]} on {sys.platform}; log:\n{self.last_log}")
        self.assert_counting_is_right(audit)

    def test_a_launch_that_raises_two_events_is_counted_once(self) -> None:
        # `close_fds=False` starts the child with posix_spawn: `subprocess.Popen` and then `os.posix_spawn` are
        # raised for the one launch (recent Linux builds do that by default, so does this call on macOS)
        events = (
            "import os, subprocess, sys\n"
            "log = []\n"
            "sys.addaudithook(lambda e, a: log.append(e) if e in ('subprocess.Popen', 'os.posix_spawn', 'os.exec', 'os.spawn') else None)\n"
            "subprocess.run([sys.executable, '-c', 'pass'], close_fds=False)\n"
            "print(log, file=sys.stderr)\n"
        )
        audit = self.python_children_are_counted(events + "subprocess.run([sys.executable, '-c', 'pass'], close_fds=False)\n")
        self.assertEqual((len(audit.starts), len(audit.launches)), (3, 2), f"python {sys.version.split()[0]} on {sys.platform}; log:\n{self.last_log}")
        self.assert_counting_is_right(audit)

    def test_a_posix_spawn_after_a_popen_with_another_environment_is_a_launch_of_its_own(self) -> None:
        # the same program and arguments, directly after the Popen, but an empty environment: the child does not
        # load the hook, and the two launches must not be counted as one
        audit = self.python_children_are_counted(
            "import os, subprocess, sys\n"
            "args = [sys.executable, '-c', 'pass']\n"
            "subprocess.run(args, close_fds=False)\n"
            "os.waitpid(os.posix_spawn(sys.executable, args, {}), 0)\n"
        )
        self.assertEqual(len(audit.launches), 2, self.last_log)
        self.assertIn("Python processes loaded the hook", su.not_recorded_why(audit, sys.executable, sys.version))

    def test_a_direct_posix_spawn_is_counted_once(self) -> None:
        audit = self.python_children_are_counted(
            "import os, sys\n"
            "os.waitpid(os.posix_spawn(sys.executable, [sys.executable, '-c', 'pass'], os.environ), 0)\n"
        )
        self.assertEqual((len(audit.starts), len(audit.launches)), (2, 1), self.last_log)
        self.assert_counting_is_right(audit)

    def test_a_listing_outside_the_repository_is_an_outside_input(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other).resolve()
            (outside / "a.txt").write_text("a")
            stdlib = os.path.dirname(os.__file__)
            audit = self.run_script(
                "import glob, os\n"
                f"os.listdir({str(outside)!r})\n"
                f"list(os.scandir({str(outside)!r}))\n"
                f"glob.glob({str(outside / '*.txt')!r})\n"
                f"os.listdir({stdlib!r})\n"  # the standard library is the interpreter's own
            )
        self.assertEqual(self.mine(audit), [str(outside), str(outside / "*.txt")])
        self.assertIn("outside the repository", su.not_recorded_why(audit, sys.executable, sys.version))

    def test_an_installed_package_is_an_outside_input_but_the_standard_library_is_not(self) -> None:
        import sysconfig

        site = Path(sysconfig.get_path("purelib")).resolve()
        found = next((p for p in site.rglob("*.py") if "__pycache__" not in p.parts), None)
        if found is None:
            self.skipTest("no installed package")
        audit = self.run_script(f"import json\nopen({str(found)!r}).read()\n")  # purelib is usually below the standard library path
        self.assertEqual(self.mine(audit), [os.path.realpath(found)])
        self.assertIn("outside the repository", su.not_recorded_why(audit, sys.executable, sys.version))

    def test_a_name_cannot_forge_a_line_of_the_log(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other).resolve() / "cache.txt"
            outside.write_text("x")
            for ending in ("\r", "\x0b", "\x0c", "\x1c", "\x85", "\u2028", "\n"):
                name = f"x{ending}C {outside}"
                audit = self.run_script(
                    "import os\n"
                    f"try:\n    os.listdir({name!r})\nexcept OSError:\n    pass\n"  # a name that does not exist, listed
                    f"open({str(outside)!r}).read()\n"
                )
                self.assertEqual(self.mine(audit), [str(outside)], repr(ending))
                self.assertTrue(any(item.startswith("x\\u") for item in audit.listings), (repr(ending), audit.listings))  # the name is there, escaped
        forged = su.parse_audit("D a\rC /x\x85C /y\u2028C /z\nX /x\n")  # a log that a hook of another version wrote
        self.assertEqual(forged.outside, ("/x",))

    def test_a_compiled_module_read_from_the_tree_is_not_recorded(self) -> None:
        audit = su.parse_audit(f"{START}R tools/check.py\nR tools/__pycache__/check.cpython-313.pyc\n")
        self.assertEqual(su.compiled_reads(audit), ["tools/__pycache__/check.cpython-313.pyc"])
        self.assertIn("compiled module", su.not_recorded_why(audit, sys.executable, VERSION))

    def test_another_interpreter_than_the_one_of_the_key_is_not_recorded(self) -> None:
        audit = su.parse_audit(f"{START}B 4243 3.14.0 (other)\nL /usr/bin/python3\nR tools/check.py\n")
        self.assertIn("another version", su.not_recorded_why(audit, sys.executable, VERSION))
        self.assertEqual(su.not_recorded_why(su.parse_audit(START + "R tools/check.py\n"), sys.executable, VERSION), "")


class InterpreterTest(unittest.TestCase):
    def test_the_version_of_the_interpreter_that_runs_the_stage_is_asked_of_it(self) -> None:
        self.assertEqual(su.interpreter_version((sys.executable, "tools/check.py")), sys.version.replace("\n", " "))
        self.assertEqual(su.interpreter_version(("sh", "x")), "")  # not a Python stage
        self.assertEqual(su.interpreter_version(("python3-does-not-exist", "x")), "")


class Fixture(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        files = {
            "library/moon.mod": 'name = "Luna-Flow/floating"\n',
            "tooling/moon.mod": 'name = "Luna-Flow/floating-tools"\nsource = "src"\n',
            "moon.work": "members = []\n",
            "tools/run_moon_clean_exec.sh": "exec moon \"$@\"\n",
            su.AUDIT_FILE: "# hook\n",
            "library/src/def/moon.pkg": "",
            "library/src/def/a.mbt": "fn a() -> Int { 1 }\n",
            "library/src/low/moon.pkg": f'import {{ "{L}/def" }}\n',
            "library/src/low/b.mbt": "fn b() -> Int { 2 }\n",
            "library/src/other/moon.pkg": f'import {{ "{L}/def" }}\n',
            "library/src/other/d.mbt": "fn d() -> Int { 4 }\n",
            "library/src/io/moon.pkg": 'import { "moonbitlang/x/fs" }\n',
            "library/src/io/e.mbt": "fn e() -> Int { 5 }\n",
            "tools/check.py": "print('x')\n",
            "tools/unrelated.py": "print('y')\n",
            "data/x.itl": "x\n",
            "elsewhere/y.txt": "y\n",
        }
        for name, text in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        patcher = patch.dict(su.SPECS, {"t": (SPEC_MOON, SPEC_PY)})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.stages = [("T: moon", ("sh", "x", "test")), ("T: python", ("python3", "tools/check.py"))]

    def plan(self, scope: str = "t", dry: str = "dry", version: str = VERSION) -> su.Plan:
        return su.make_plan(scope, self.stages, self.root, inc.Ledger(self.root / "ledger.jsonl"), 1, rate=0.0, environ={}, run=lambda *a, **k: dry, ask_version=lambda command: version)

    def edit(self, name: str, text: str = "// edit\n") -> None:
        with (self.root / name).open("a") as stream:
            stream.write(text)


class MutationTest(Fixture):
    """Which units a change reaches (synthetic repository of the same shape)."""

    def changed(self, before: su.Plan, after: su.Plan) -> set[str]:
        return {u for u in after.keys if before.keys.get(u) != after.keys[u]}

    def test_a_package_in_the_closure_reaches_the_moon_unit_only(self) -> None:
        base = self.plan()
        self.assertEqual(set(base.keys), {"T: moon", "T: python"})
        self.edit("library/src/def/a.mbt")
        self.assertEqual(self.changed(base, self.plan()), {"T: moon"})

    def test_a_package_outside_the_closure_reaches_nothing(self) -> None:
        base = self.plan()
        self.edit("library/src/other/d.mbt")
        self.assertEqual(self.changed(base, self.plan()), set())

    def test_a_declared_file_or_directory_reaches_the_python_unit_only(self) -> None:
        base = self.plan()
        self.edit("tools/check.py")
        self.assertEqual(self.changed(base, self.plan()), {"T: python"})
        base = self.plan()
        self.edit("data/x.itl")
        self.assertEqual(self.changed(base, self.plan()), {"T: python"})
        base = self.plan()
        (self.root / "data/new.itl").write_text("new")  # a new file in a declared directory
        self.assertEqual(self.changed(base, self.plan()), {"T: python"})

    def test_an_undeclared_file_reaches_nothing_which_is_why_the_audit_exists(self) -> None:
        base = self.plan()
        self.edit("tools/unrelated.py")
        self.edit("elsewhere/y.txt")
        self.assertEqual(self.changed(base, self.plan()), set())

    def test_module_files_the_wrapper_and_the_hook_reach_the_right_units(self) -> None:
        base = self.plan()
        self.edit("moon.work", "# x\n")
        self.assertEqual(self.changed(base, self.plan()), {"T: moon"})
        base = self.plan()
        self.edit("tools/run_moon_clean_exec.sh", "# x\n")
        self.assertEqual(self.changed(base, self.plan()), {"T: moon"})
        base = self.plan()
        self.edit(su.AUDIT_FILE, "# x\n")
        self.assertEqual(self.changed(base, self.plan()), {"T: moon", "T: python"})  # the hook directory is an input of every unit
        base = self.plan()
        (self.root / su.AUDIT_DIR / "second.py").write_text("x")  # any file of that directory
        self.assertEqual(self.changed(base, self.plan()), {"T: moon", "T: python"})
        base = self.plan()
        self.assertEqual(self.changed(base, self.plan(dry="another command line")), {"T: moon"})

    def test_the_version_of_the_stage_interpreter_is_in_the_key_of_the_python_unit_only(self) -> None:
        base = self.plan()
        self.assertEqual(self.changed(base, self.plan(version="3.14.0 (other)")), {"T: python"})

    def test_a_python_unit_whose_interpreter_cannot_be_asked_is_not_keyed(self) -> None:
        plan = self.plan(version="")
        self.assertIn("T: python", plan.unit_disabled)
        self.assertNotIn("T: python", plan.keys)
        self.assertIn("T: moon", plan.keys)

    def test_a_missing_declared_file_disables_reuse_and_so_does_a_dry_run_without_output(self) -> None:
        (self.root / "tools/check.py").unlink()
        self.assertIn("does not exist", self.plan().disabled)
        (self.root / "tools/check.py").write_text("x")
        self.assertIn("could not print", self.plan(dry="").disabled)

    def test_a_moon_unit_whose_closure_imports_the_file_system_is_not_keyed(self) -> None:
        spec = su.StageSpec("T: moon", "moon", (f"{L}/io",))
        with patch.dict(su.SPECS, {"t": (spec,)}):
            plan = self.plan()
        self.assertIn("T: moon", plan.unit_disabled)
        self.assertNotIn("T: moon", plan.keys)


class RunStageTest(Fixture):
    def setUp(self) -> None:
        super().setUp()
        original = su.unchanged
        su.unchanged = lambda plan, unit: True  # type: ignore[assignment]
        self.addCleanup(setattr, su, "unchanged", original)
        self.lines: list[str] = []
        self.tally = su.Tally()
        self.commits: dict[str, int] = {}

    @staticmethod
    def python_ran(env, log: str) -> tuple[int, str]:  # noqa: ANN001
        """What a Python stage that started the hook and then wrote `log` leaves behind."""
        Path(env["STAGE_AUDIT_LOG"]).write_text(START + log)
        return 0, ""

    def run_one(self, plan: su.Plan, name: str, execute) -> int:  # noqa: ANN001
        unit = next(u for u in plan.units if u.name == name)
        return su.run_stage(plan, unit, execute, self.tally, self.commits, self.lines.append, environ={})

    def test_a_pass_is_recorded_and_the_next_run_reuses_it_without_executing(self) -> None:
        plan = self.plan()
        for name in ("T: moon", "T: python"):
            self.assertEqual(self.run_one(plan, name, lambda c, e: OK if "test" in c else self.python_ran(e, "")), 0)
        self.assertEqual(self.tally.ran, 2)
        self.assertTrue(all(plan.ledger.result(k) for k in plan.keys.values()))
        again = self.plan()
        again.actions = {"T: moon": "reuse", "T: python": "reuse"}
        calls: list[tuple[str, ...]] = []
        for name in ("T: moon", "T: python"):
            self.assertEqual(self.run_one(again, name, lambda c, e: calls.append(c) or (1, "")), 0)
        self.assertEqual(calls, [])
        self.assertEqual(sum(line.startswith("REUSED") for line in self.lines), 2)
        self.assertFalse(any(line.startswith("PASS") and "REUSED" in line for line in self.lines))

    def test_a_moon_stage_with_zero_tests_or_a_missing_package_fails_and_records_nothing(self) -> None:
        for text in ("Total tests: 0, passed: 0, failed: 0.\n", "Warning: package x not found\nTotal tests: 5, passed: 5, failed: 0.\n", "no line\n"):
            plan = self.plan()
            self.assertEqual(self.run_one(plan, "T: moon", lambda c, e, t=text: (0, t)), 1, text)
            self.assertIsNone(plan.ledger.result(plan.keys["T: moon"]))

    def test_a_sampled_rerun_that_fails_is_a_defect(self) -> None:
        plan = self.plan()
        plan.actions["T: moon"] = "sample"
        self.assertEqual(self.run_one(plan, "T: moon", lambda c, e: (1, "Total tests: 1, passed: 0, failed: 1.")), inc.EXIT_DEFECT)

    def test_a_python_stage_that_reads_outside_its_declaration_is_a_defect_and_is_not_recorded(self) -> None:
        plan = self.plan()

        def execute(command: tuple[str, ...], env) -> tuple[int, str]:  # noqa: ANN001
            return self.python_ran(env, "R tools/check.py\nR data/x.itl\nR elsewhere/y.txt\nD elsewhere\n")  # a new input, not declared

        status = self.run_one(plan, "T: python", execute)
        self.assertEqual(status, inc.EXIT_DEFECT)
        self.assertIsNone(plan.ledger.result(plan.keys["T: python"]))
        self.assertTrue(any("elsewhere/y.txt" in line and "declaration" in line for line in self.lines))

    def test_a_python_stage_reading_only_declared_files_is_recorded(self) -> None:
        plan = self.plan()

        def execute(command: tuple[str, ...], env) -> tuple[int, str]:  # noqa: ANN001
            return self.python_ran(env, "R tools/check.py\nR data/x.itl\nD data\nD tools/stage_audit\nR tools/stage_audit/sitecustomize.py\n")

        self.assertEqual(self.run_one(plan, "T: python", execute), 0)
        self.assertIsNotNone(plan.ledger.result(plan.keys["T: python"]))

    def test_a_python_stage_that_starts_another_program_passes_but_is_not_recorded(self) -> None:
        plan = self.plan()

        def execute(command: tuple[str, ...], env) -> tuple[int, str]:  # noqa: ANN001
            return self.python_ran(env, "R tools/check.py\nS /usr/bin/mpfr-tool\n")

        self.assertEqual(self.run_one(plan, "T: python", execute), 0)
        self.assertIsNone(plan.ledger.result(plan.keys["T: python"]))
        self.assertTrue(any("not recorded" in line for line in self.lines))

    def test_a_python_stage_without_a_start_line_passes_but_is_not_recorded(self) -> None:
        plan = self.plan()

        def execute(command: tuple[str, ...], env) -> tuple[int, str]:  # noqa: ANN001
            subprocess.run([sys.executable, "-I", "-c", "open('tools/check.py').read()"], cwd=self.root, env=env, check=True)  # the hook is not loaded
            return 0, ""

        self.assertEqual(self.run_one(plan, "T: python", execute), 0)
        self.assertIsNone(plan.ledger.result(plan.keys["T: python"]))
        self.assertTrue(any("not recorded" in line and "did not start" in line for line in self.lines))
        self.assertEqual(self.tally.unrecorded, 1)

    def test_a_python_stage_that_reads_outside_the_repository_is_not_recorded_but_its_own_files_are_fine(self) -> None:
        plan = self.plan()
        self.assertEqual(self.run_one(plan, "T: python", lambda c, e: self.python_ran(e, "R tools/check.py\nX /var/cache/tool.json\n")), 0)
        self.assertIsNone(plan.ledger.result(plan.keys["T: python"]))
        self.assertTrue(any("not recorded" in line and "/var/cache/tool.json" in line for line in self.lines))
        plan = self.plan()
        self.assertEqual(self.run_one(plan, "T: python", lambda c, e: self.python_ran(e, "R tools/check.py\nC /tmp/x.json\nX /tmp/x.json\n")), 0)
        self.assertIsNotNone(plan.ledger.result(plan.keys["T: python"]))

    def test_a_python_stage_run_by_another_version_than_the_key_is_not_recorded(self) -> None:
        plan = self.plan()

        def execute(command: tuple[str, ...], env) -> tuple[int, str]:  # noqa: ANN001
            Path(env["STAGE_AUDIT_LOG"]).write_text("B 4243 3.14.0 (a Python the verifier did not ask)\nR tools/check.py\n")
            return 0, ""

        self.assertEqual(self.run_one(plan, "T: python", execute), 0)
        self.assertIsNone(plan.ledger.result(plan.keys["T: python"]))

    def test_every_python_run_gets_a_private_cache_directory_that_is_removed_after_it(self) -> None:
        plan = self.plan()
        seen: list[Path] = []

        def execute(command: tuple[str, ...], env) -> tuple[int, str]:  # noqa: ANN001
            seen.append(Path(env["PYTHONPYCACHEPREFIX"]))
            self.assertEqual(list(seen[0].iterdir()), [])
            self.assertEqual(env["STAGE_AUDIT_EXEMPT"], env["PYTHONPYCACHEPREFIX"])
            return self.python_ran(env, "R tools/check.py\n")

        self.assertEqual(self.run_one(plan, "T: python", execute), 0)
        self.assertFalse(seen[0].exists())

    def test_a_stage_that_reads_git_or_a_pycache_file_is_undeclared(self) -> None:
        for path in (".git/HEAD", "data/__pycache__/state.json"):  # the second lies below a declared directory
            plan = self.plan()
            status = self.run_one(plan, "T: python", lambda c, e, p=path: self.python_ran(e, f"R tools/check.py\nR {p}\n"))
            self.assertEqual(status, inc.EXIT_DEFECT, path)
            self.assertIsNone(plan.ledger.result(plan.keys["T: python"]))

    def test_a_not_keyed_moon_unit_runs_and_says_why(self) -> None:
        spec = su.StageSpec("T: moon", "moon", (f"{L}/io",))
        with patch.dict(su.SPECS, {"t": (spec,)}):
            plan = self.plan()
        self.assertEqual(self.run_one(plan, "T: moon", lambda c, e: OK), 0)
        self.assertTrue(any("not keyed" in line for line in self.lines))

    def test_a_disabled_plan_runs_every_stage(self) -> None:
        plan = self.plan()
        plan.disabled = "no key can be formed: x"
        calls: list[int] = []
        self.assertEqual(self.run_one(plan, "T: moon", lambda c, e: calls.append(1) or OK), 0)
        self.assertEqual(calls, [1])
        self.assertEqual(self.tally.reused, 0)


class RealRepositoryTest(unittest.TestCase):
    def test_the_specs_name_stages_of_the_gates_and_declare_files_that_exist(self) -> None:
        import run_ci

        for scope, specs in su.SPECS.items():
            names = [s.name for s in run_ci.stages_for(scope, 3)]
            for spec in specs:
                self.assertIn(spec.stage, names, spec.stage)
                for item in spec.declared:
                    self.assertTrue((su.nu.REPO_ROOT / item.rstrip("/")).exists(), item)

    def test_the_moon_specs_have_pure_closures(self) -> None:
        packages = su.nu.discover_packages(su.nu.REPO_ROOT)
        for specs in su.SPECS.values():
            for spec in specs:
                if spec.kind == "moon":
                    self.assertEqual(su.nu.impure_imports(spec.packages, packages), [], spec.stage)


if __name__ == "__main__":
    unittest.main()
