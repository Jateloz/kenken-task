"""Validates the KenKen game implementation: engine correctness, command parsing, and UI artefacts."""

import subprocess
import json
from pathlib import Path


def _node(script: str) -> dict:
    """Run an ES module snippet and return its JSON output as a dict."""
    r = subprocess.run(
        ["node", "--input-type=module"],
        input=script,
        capture_output=True,
        text=True,
        cwd="/app",
        timeout=15,
    )
    assert r.returncode == 0, f"Node error:\n{r.stderr}"
    return json.loads(r.stdout.strip())


def test_engine_file_exists():
    """The engine module must be present at /app/src/engine/kenken-engine.js before any runtime test runs."""
    assert Path("/app/src/engine/kenken-engine.js").exists()


def test_parser_file_exists():
    """The command parser must be present at /app/src/engine/command-parser.js before any runtime test runs."""
    assert Path("/app/src/engine/command-parser.js").exists()


def test_index_html_exists():
    """The game entry point must be present at /app/index.html so the verifier can serve it."""
    assert Path("/app/index.html").exists()


def test_6x6_grid_dimensions():
    """newPuzzle(6) must return a 6×6 grid containing at least one cage."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
const d = e.getPuzzleData();
console.log(JSON.stringify({ size: d.size, rows: d.grid.length, cols: d.grid[0].length, cages: d.cages.length }));
""")
    assert out["size"] == 6
    assert out["rows"] == 6
    assert out["cols"] == 6
    assert out["cages"] > 0


def test_4x4_grid_dimensions():
    """newPuzzle(4) must produce a 4×4 grid — confirming both supported sizes work."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(4);
const d = e.getPuzzleData();
console.log(JSON.stringify({ size: d.size, rows: d.grid.length }));
""")
    assert out["size"] == 4
    assert out["rows"] == 4


def test_fresh_grid_is_empty():
    """Every cell must start at 0 on a newly generated puzzle."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
const d = e.getPuzzleData();
console.log(JSON.stringify({ empty: d.grid.every(r => r.every(v => v === 0)) }));
""")
    assert out["empty"] is True


def test_solve_produces_valid_latin_square():
    """solvePuzzle must produce a grid where every row and column contains digits 1–6 without repetition."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
e.solvePuzzle();
const d = e.getPuzzleData();
let valid = true;
for (let i = 0; i < d.size; i++) {
  if (new Set(d.grid[i]).size !== d.size) valid = false;
  if (new Set(d.grid.map(r => r[i])).size !== d.size) valid = false;
}
console.log(JSON.stringify({ valid }));
""")
    assert out["valid"] is True


def test_correct_move_accepted():
    """getMoveResult returns code 0 when the proposed digit matches the solution at that position."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
e.solvePuzzle();
const sol = e.getPuzzleData().grid.map(r => [...r]);
e.resetBoard();
const res = e.getMoveResult(0, 0, sol[0][0]);
console.log(JSON.stringify({ ok: res.ok, code: res.code }));
""")
    assert out["ok"] is True
    assert out["code"] == 0


def test_wrong_value_rejected():
    """getMoveResult returns code 4 for a digit that is in range but not the solution value."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
e.solvePuzzle();
const sol = e.getPuzzleData().grid.map(r => [...r]);
e.resetBoard();
const correct = sol[0][0];
const wrong = correct === 6 ? 5 : correct + 1;
const res = e.getMoveResult(0, 0, wrong);
console.log(JSON.stringify({ ok: res.ok, code: res.code }));
""")
    assert out["ok"] is False
    assert out["code"] == 4


def test_out_of_range_rejected():
    """getMoveResult returns code 1 for a digit outside the valid range for the puzzle size."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
const res = e.getMoveResult(0, 0, 7);
console.log(JSON.stringify({ ok: res.ok, code: res.code }));
""")
    assert out["ok"] is False
    assert out["code"] == 1


def test_check_complete_after_solve():
    """getCheckResult must report complete=true and filled=36 after the puzzle is auto-solved."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
e.solvePuzzle();
const res = e.getCheckResult();
console.log(JSON.stringify({ complete: res.complete, filled: res.filled, total: res.total }));
""")
    assert out["complete"] is True
    assert out["filled"] == 36
    assert out["total"] == 36


def test_cages_cover_all_cells():
    """The union of all cage cells must cover every position in a 6×6 grid with no gaps."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
const e = new KenKenEngine();
e.newPuzzle(6);
const d = e.getPuzzleData();
const covered = new Set();
d.cages.forEach(cage => cage.cells.forEach(c => covered.add(c.row + ',' + c.col)));
console.log(JSON.stringify({ covered: covered.size }));
""")
    assert out["covered"] == 36


def test_help_command():
    """parseCommand('help') must return ok=true with type='help'."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
import { parseCommand } from '/app/src/engine/command-parser.js';
const e = new KenKenEngine(); e.newPuzzle(6);
const r = parseCommand('help', e);
console.log(JSON.stringify({ ok: r.ok, type: r.type }));
""")
    assert out["ok"] is True
    assert out["type"] == "help"


def test_unknown_command_returns_error():
    """parseCommand with an unrecognised input must return ok=false and type='error'."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
import { parseCommand } from '/app/src/engine/command-parser.js';
const e = new KenKenEngine(); e.newPuzzle(6);
const r = parseCommand('frobnicate', e);
console.log(JSON.stringify({ ok: r.ok, type: r.type }));
""")
    assert out["ok"] is False
    assert out["type"] == "error"


def test_solve_command_fills_grid():
    """parseCommand('solve') must delegate to the engine and leave every cell non-zero."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
import { parseCommand } from '/app/src/engine/command-parser.js';
const e = new KenKenEngine(); e.newPuzzle(6);
parseCommand('solve', e);
const filled = e.getPuzzleData().grid.every(row => row.every(v => v > 0));
console.log(JSON.stringify({ filled }));
""")
    assert out["filled"] is True


def test_new_invalid_size_rejected():
    """parseCommand('new 9') must return ok=false — only sizes 4 and 6 are accepted."""
    out = _node("""
import { KenKenEngine } from '/app/src/engine/kenken-engine.js';
import { parseCommand } from '/app/src/engine/command-parser.js';
const e = new KenKenEngine(); e.newPuzzle(6);
const r = parseCommand('new 9', e);
console.log(JSON.stringify({ ok: r.ok }));
""")
    assert out["ok"] is False


def test_index_contains_required_ui_elements():
    """The index.html must contain all required data-testid attributes and CSS class anchors."""
    html = Path("/app/index.html").read_text()
    assert 'data-testid="terminal-output"' in html
    assert 'data-testid="cmd-input"' in html
    assert 'data-testid="win-overlay"' in html
    assert 'kk-size-btn' in html
    assert 'kk-mode-badge' in html
    assert 'kk-cage-label' in html
    assert 'kk-stat' in html
