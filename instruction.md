Build a browser-based KenKen puzzle game at /app/index.html served at the root URL (/).

KenKen rules: fill an N×N grid so every row and column contains each digit 1 through N exactly once. Each outlined cage must produce its target number using the labelled operation (+, −, ×, ÷, or a lone digit for a single-cell cage).

The game must be implemented as three separate ES modules and one HTML file:

/app/src/engine/kenken-engine.js — export class KenKenEngine with: newPuzzle(size), getMoveResult(row, col, val), applyMove(row, col, val), clearCell(row, col), getCheckResult(), getHint(), getPuzzleData(), solvePuzzle(), resetBoard(), getSize(). getMoveResult returns { ok, code, message, hintVal } where code is 0=VALID 1=INVALID_RANGE 2=ROW_CONFLICT 3=COL_CONFLICT 4=WRONG_VALUE.

/app/src/engine/command-parser.js — export function parseCommand(input, engine) returning { ok, type, message, data? }. Support: set <row> <col> <val>, clear <row> <col>, hint, check, solve, reset, new <size>, status, help. Unknown input returns { ok: false, type: "error" }. new only accepts size 4 or 6.

/app/index.html — self-contained static HTML, no build step. Import the two engine files as ES modules. The page must have a 6×6 default grid with cells carrying data-testid="cell-R-C", a data-testid="terminal-output" console panel, a data-testid="cmd-input" command input that runs commands on Enter, a data-testid="win-overlay" that appears when the puzzle is solved, kk-size-btn buttons that switch between 4×4 and 6×6, a kk-mode-badge element that toggles between Normal and Pencil text, kk-cage-label elements on the grid, and kk-stat elements showing moves, errors, time, and fill percentage.
