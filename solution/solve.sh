#!/bin/bash
set -euo pipefail

mkdir -p /app/src/engine

cat > /app/src/engine/kenken-engine.js << 'JSEOF'
const MoveCode = { VALID: 0, INVALID_RANGE: 1, ROW_CONFLICT: 2, COL_CONFLICT: 3, WRONG_VALUE: 4 };

class PuzzleGenerator {
  constructor(seed) {
    this.s = seed ?? Date.now();
  }

  rng() {
    this.s = (this.s * 1664525 + 1013904223) & 0xffffffff;
    return (this.s >>> 0) / 0x100000000;
  }

  generate(size) {
    const solution = this.latinSquare(size);
    const cages = this.buildCages(solution, size);
    const grid = Array.from({ length: size }, () => Array(size).fill(0));
    return { grid, solution, cages };
  }

  latinSquare(n) {
    const sol = Array.from({ length: n }, (_, r) =>
      Array.from({ length: n }, (_, c) => (r + c) % n + 1)
    );
    const cols = Array.from({ length: n }, (_, i) => i);
    const rows = Array.from({ length: n }, (_, i) => i);
    for (let i = n - 1; i > 0; i--) {
      const j = Math.floor(this.rng() * (i + 1));
      [cols[i], cols[j]] = [cols[j], cols[i]];
    }
    for (let i = n - 1; i > 0; i--) {
      const j = Math.floor(this.rng() * (i + 1));
      [rows[i], rows[j]] = [rows[j], rows[i]];
    }
    const tmp = sol.map(r => r.map((_, c) => r[cols[c]]));
    return rows.map(r => tmp[r]);
  }

  buildCages(sol, size) {
    const vis = Array.from({ length: size }, () => Array(size).fill(false));
    const dirs = [[0, 1], [1, 0], [0, -1], [-1, 0]];
    const cages = [];
    let id = 0;
    for (let r = 0; r < size; r++) {
      for (let c = 0; c < size; c++) {
        if (vis[r][c]) continue;
        vis[r][c] = true;
        const cells = [{ row: r, col: c }];
        const want = 1 + Math.floor(this.rng() * (size <= 4 ? 3 : 4));
        for (let a = 0; a < 20 && cells.length < want; a++) {
          const { row: lr, col: lc } = cells[Math.floor(this.rng() * cells.length)];
          const [dr, dc] = dirs[Math.floor(this.rng() * 4)];
          const nr = lr + dr, nc = lc + dc;
          if (nr >= 0 && nr < size && nc >= 0 && nc < size && !vis[nr][nc]) {
            vis[nr][nc] = true;
            cells.push({ row: nr, col: nc });
          }
        }
        cages.push(this.makeCage(cells, sol, size, id++));
      }
    }
    return cages;
  }

  makeCage(cells, sol, size, id) {
    const vals = cells.map(({ row: r, col: c }) => sol[r][c]);
    if (cells.length === 1) return { target: vals[0], op: '', id, cells };
    const sum = vals.reduce((a, b) => a + b, 0);
    const prod = vals.reduce((a, b) => a * b, 1);
    const [a, b] = [...vals].sort((x, y) => y - x);
    const choices = [['+', sum]];
    if (prod <= size * size) choices.push(['\xd7', prod]);
    if (cells.length === 2) {
      choices.push(['\u2212', a - b]);
      if (b > 0 && a % b === 0) choices.push(['\xf7', a / b]);
    }
    const [op, target] = choices[Math.floor(this.rng() * choices.length)];
    return { target, op, id, cells };
  }
}

function cageCheck(op, target, vals) {
  if (op === '') return vals.length === 1 && vals[0] === target;
  if (op === '+') return vals.reduce((a, b) => a + b, 0) === target;
  if (op === '\xd7') return vals.reduce((a, b) => a * b, 1) === target;
  if (op === '\u2212') { const [a, b] = [...vals].sort((x, y) => y - x); return a - b === target; }
  if (op === '\xf7') { const [a, b] = [...vals].sort((x, y) => y - x); return b > 0 && a % b === 0 && a / b === target; }
  return false;
}

function cageSatisfied(cage, grid) {
  const vals = cage.cells.map(({ row: r, col: c }) => grid[r][c]);
  return !vals.some(v => v === 0) && cageCheck(cage.op, cage.target, vals);
}

export class KenKenEngine {
  constructor() {
    this._size = 0;
    this._grid = [];
    this._solution = [];
    this._cages = [];
  }

  newPuzzle(size) {
    const p = new PuzzleGenerator().generate(size);
    this._size = size;
    this._grid = p.grid;
    this._solution = p.solution;
    this._cages = p.cages;
  }

  getMoveResult(row, col, val) {
    if (val < 1 || val > this._size)
      return { ok: false, code: MoveCode.INVALID_RANGE, message: 'Value out of range', hintVal: -1 };
    for (let i = 0; i < this._size; i++)
      if (i !== col && this._grid[row][i] === val)
        return { ok: false, code: MoveCode.ROW_CONFLICT, message: 'Row conflict', hintVal: -1 };
    for (let i = 0; i < this._size; i++)
      if (i !== row && this._grid[i][col] === val)
        return { ok: false, code: MoveCode.COL_CONFLICT, message: 'Col conflict', hintVal: -1 };
    if (this._solution[row][col] !== val)
      return { ok: false, code: MoveCode.WRONG_VALUE, message: 'Incorrect', hintVal: this._solution[row][col] };
    return { ok: true, code: MoveCode.VALID, message: 'OK', hintVal: -1 };
  }

  applyMove(row, col, val) {
    const res = this.getMoveResult(row, col, val);
    if (res.ok) this._grid[row][col] = val;
    return res.ok;
  }

  clearCell(row, col) {
    if (this._grid[row]) this._grid[row][col] = 0;
  }

  getCheckResult() {
    const total = this._size * this._size;
    const filled = this._grid.flat().filter(v => v > 0).length;
    const res = { complete: false, filled, total, rowErrors: [], colErrors: [], cageErrors: [] };
    if (filled < total) return res;
    for (let i = 0; i < this._size; i++) {
      if (new Set(this._grid[i]).size < this._size) res.rowErrors.push(i);
      if (new Set(this._grid.map(r => r[i])).size < this._size) res.colErrors.push(i);
    }
    this._cages.forEach((cage, idx) => {
      if (!cageSatisfied(cage, this._grid)) res.cageErrors.push(idx);
    });
    res.complete = !res.rowErrors.length && !res.colErrors.length && !res.cageErrors.length;
    return res;
  }

  getHint() {
    const empties = [];
    for (let r = 0; r < this._size; r++)
      for (let c = 0; c < this._size; c++)
        if (!this._grid[r][c]) empties.push([r, c]);
    if (!empties.length) return { found: false };
    const [row, col] = empties[Math.floor(Math.random() * empties.length)];
    return { found: true, row, col, val: this._solution[row][col] };
  }

  getPuzzleData() {
    return { size: this._size, grid: this._grid.map(r => [...r]), cages: this._cages };
  }

  solvePuzzle() {
    this._grid = this._solution.map(r => [...r]);
    return true;
  }

  resetBoard() {
    this._grid = Array.from({ length: this._size }, () => Array(this._size).fill(0));
  }

  getSize() {
    return this._size;
  }
}
JSEOF

cat > /app/src/engine/command-parser.js << 'JSEOF'
export function parseCommand(input, engine) {
  const parts = (input ?? '').trim().split(/\s+/).filter(Boolean);
  const op = (parts[0] ?? '').toLowerCase();

  if (op === 'set') {
    const r = parseInt(parts[1]) - 1;
    const c = parseInt(parts[2]) - 1;
    const v = parseInt(parts[3]);
    if (isNaN(r) || isNaN(c) || isNaN(v) || parts.length < 4)
      return { ok: false, type: 'set', message: 'usage: set <row> <col> <val>' };
    const move = engine.getMoveResult(r, c, v);
    if (move.ok) engine.applyMove(r, c, v);
    return { ok: move.ok, type: 'set', message: move.message, data: move };
  }

  if (op === 'clear') {
    const r = parseInt(parts[1]) - 1;
    const c = parseInt(parts[2]) - 1;
    if (isNaN(r) || isNaN(c))
      return { ok: false, type: 'clear', message: 'usage: clear <row> <col>' };
    engine.clearCell(r, c);
    return { ok: true, type: 'clear', message: `(${r + 1},${c + 1}) cleared` };
  }

  if (op === 'hint') {
    const hint = engine.getHint();
    return {
      ok: hint.found,
      type: 'hint',
      message: hint.found ? `(${hint.row + 1},${hint.col + 1}) \u2192 try ${hint.val}` : 'no empty cells',
      data: hint,
    };
  }

  if (op === 'check') {
    const res = engine.getCheckResult();
    return {
      ok: true,
      type: 'check',
      message: res.complete ? 'valid and complete' : `${res.filled}/${res.total} filled`,
      data: res,
    };
  }

  if (op === 'solve') {
    engine.solvePuzzle();
    return { ok: true, type: 'solve', message: 'solved' };
  }

  if (op === 'reset') {
    engine.resetBoard();
    return { ok: true, type: 'reset', message: 'board cleared' };
  }

  if (op === 'new') {
    const size = parseInt(parts[1]);
    if (size !== 4 && size !== 6)
      return { ok: false, type: 'new', message: 'size must be 4 or 6' };
    engine.newPuzzle(size);
    return { ok: true, type: 'new', message: `${size}\xd7${size} puzzle loaded` };
  }

  if (op === 'status') {
    const d = engine.getPuzzleData();
    const filled = d.grid.flat().filter(v => v > 0).length;
    return { ok: true, type: 'status', message: `${filled}/${d.size * d.size} filled` };
  }

  if (op === 'help') {
    return {
      ok: true,
      type: 'help',
      message: 'available commands',
      data: ['set <row> <col> <val>', 'clear <row> <col>', 'hint', 'check', 'solve', 'reset', 'new [4|6]', 'status', 'pencil', 'help'],
    };
  }

  return { ok: false, type: 'error', message: `unknown command '${op}'` };
}
JSEOF


cat > /app/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>KenKen</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,300;1,9..144,300&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{background:#f5f4f0;color:#1a1a18;font-family:'DM Mono',monospace;font-size:13px;-webkit-font-smoothing:antialiased}
:root{
  --ink:#1a1a18;--ink2:#4a4a46;--ink3:#9a9a94;--ink4:#c8c8c2;
  --paper:#f5f4f0;--paper2:#eeede8;--paper3:#e5e4de;--line:#dddcd6;
  --accent:#2a4d3a;--accent-lt:#e8f0eb;
  --danger:#8b2020;--danger-lt:#f5eaea;
  --warn:#6b5000;--warn-lt:#f5f0e0;
}
.kk-root{display:grid;grid-template-rows:56px 1fr 36px;height:100vh;overflow:hidden;background:var(--paper)}
.kk-header{display:flex;align-items:center;gap:20px;padding:0 24px;background:var(--paper);border-bottom:1px solid var(--line);flex-shrink:0}
.kk-logo{font-family:'Fraunces',Georgia,serif;font-size:20px;font-weight:300;color:var(--ink);letter-spacing:-0.02em}
.kk-logo em{font-style:italic;color:var(--accent)}
.kk-divider{width:1px;height:20px;background:var(--line)}
.kk-size-btns{display:flex;gap:4px}
.kk-size-btn{background:transparent;border:1px solid var(--line);color:var(--ink2);padding:4px 12px;border-radius:4px;cursor:pointer;font-family:'DM Mono',monospace;font-size:11px;transition:all .15s}
.kk-size-btn:hover{border-color:var(--ink3);color:var(--ink)}
.kk-size-btn.active{border-color:var(--accent);color:var(--accent);background:var(--accent-lt)}
.kk-stats{display:flex;gap:20px;margin-left:auto}
.kk-stat{display:flex;flex-direction:column;align-items:flex-end;gap:1px}
.kk-sv{font-size:14px;font-weight:500;color:var(--ink)}
.kk-sv-err{color:var(--danger)}
.kk-sl{font-size:9px;color:var(--ink3);letter-spacing:.08em;text-transform:uppercase}
.kk-mode-badge{font-size:10px;font-weight:500;padding:3px 10px;border-radius:4px;letter-spacing:.06em;text-transform:uppercase}
.kk-mode-badge.normal{background:var(--paper2);color:var(--ink3);border:1px solid var(--line)}
.kk-mode-badge.pencil{background:var(--warn-lt);color:var(--warn);border:1px solid #d4c080}
.kk-main{display:grid;grid-template-columns:1fr 320px;overflow:hidden;min-height:0}
.kk-grid-panel{display:flex;align-items:center;justify-content:center;background:var(--paper);position:relative;overflow:hidden}
.kk-grid{display:grid;gap:2px;background:var(--line);border:2px solid var(--ink4);border-radius:4px;padding:2px}
.kk-cell{background:var(--paper);display:flex;flex-direction:column;align-items:center;justify-content:center;cursor:pointer;position:relative;transition:background .1s;user-select:none}
.kk-cell:hover{background:var(--paper2)}
.kk-cell.selected{background:var(--accent-lt)!important;outline:2px solid var(--accent);outline-offset:-2px;z-index:1}
.kk-cell.flash-error{background:var(--danger-lt)!important;animation:shake .3s ease}
.kk-cell.flash-correct{background:var(--accent-lt)!important}
@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-3px)}75%{transform:translateX(3px)}}
.kk-cell.cage-top{border-top:2px solid var(--ink)!important}
.kk-cell.cage-right{border-right:2px solid var(--ink)!important}
.kk-cell.cage-bottom{border-bottom:2px solid var(--ink)!important}
.kk-cell.cage-left{border-left:2px solid var(--ink)!important}
.kk-cage-label{position:absolute;top:3px;left:4px;font-size:9px;font-weight:500;color:var(--ink2);line-height:1;pointer-events:none;z-index:2}
.kk-cell-val{font-family:'Fraunces',Georgia,serif;font-size:24px;font-weight:300;color:var(--ink);line-height:1}
.kk-cell-val.user{color:var(--accent)}
.kk-pencil-grid{display:grid;grid-template-columns:repeat(3,1fr);width:90%;gap:0}
.kk-pm{font-size:8px;color:var(--ink4);text-align:center;line-height:1.6}
.kk-pm.active{color:var(--warn)}
.kk-win-overlay{position:absolute;inset:0;background:rgba(245,244,240,.95);display:none;flex-direction:column;align-items:center;justify-content:center;gap:10px;z-index:10}
.kk-win-overlay.visible{display:flex;animation:fadein .3s ease}
@keyframes fadein{from{opacity:0}to{opacity:1}}
.kk-win-title{font-family:'Fraunces',Georgia,serif;font-size:36px;font-weight:300;color:var(--accent);letter-spacing:-0.02em}
.kk-win-sub{color:var(--ink2);font-size:12px}
.kk-win-btn{margin-top:12px;background:var(--accent);border:none;color:#fff;padding:10px 28px;cursor:pointer;font-family:'DM Mono',monospace;font-size:12px;letter-spacing:.06em;text-transform:uppercase;border-radius:4px}
.kk-win-btn:hover{opacity:.85}
.kk-sidebar{background:var(--paper2);border-left:1px solid var(--line);display:flex;flex-direction:column;overflow:hidden;min-height:0}
.kk-sidebar-label{padding:10px 16px 6px;font-size:9px;font-weight:500;letter-spacing:.1em;text-transform:uppercase;color:var(--ink3);border-bottom:1px solid var(--line);flex-shrink:0}
.kk-terminal{flex:1;overflow-y:auto;padding:12px 14px;display:flex;flex-direction:column;gap:1px}
.kk-terminal::-webkit-scrollbar{width:3px}
.kk-terminal::-webkit-scrollbar-thumb{background:var(--line)}
.kk-tline{font-size:11.5px;line-height:1.65;white-space:pre-wrap;word-break:break-all;font-family:'DM Mono',monospace;font-weight:300}
.t-system{color:var(--ink4)}.t-prompt{color:var(--ink2);font-weight:400}.t-output{color:var(--ink)}
.t-error{color:var(--danger)}.t-success{color:var(--accent)}.t-info{color:var(--ink2)}.t-warn{color:var(--warn)}.t-hint{color:var(--ink2);font-style:italic}
.kk-cursor{display:inline-block;width:6px;height:12px;background:var(--ink3);vertical-align:middle;animation:blink 1.1s step-end infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:0}}
.kk-input-row{border-top:1px solid var(--line);padding:10px 14px;display:flex;align-items:center;gap:8px;background:var(--paper);flex-shrink:0}
.kk-prompt-sym{color:var(--ink3);font-size:14px;flex-shrink:0}
.kk-cmd-input{flex:1;background:transparent;border:none;outline:none;color:var(--ink);font-family:'DM Mono',monospace;font-size:12px;caret-color:var(--accent)}
.kk-cmd-input::placeholder{color:var(--ink4)}
.kk-footer{background:var(--paper2);border-top:1px solid var(--line);padding:0 16px;display:flex;align-items:center;flex-wrap:nowrap;gap:14px;overflow:hidden;flex-shrink:0}
.kk-binding{display:flex;align-items:center;gap:5px;white-space:nowrap;font-size:10px;color:var(--ink3)}
kbd{background:var(--paper);border:1px solid var(--line);padding:1px 5px;border-radius:3px;color:var(--ink2);font-family:'DM Mono',monospace;font-size:10px}
</style>
</head>
<body>
<div class="kk-root">
  <header class="kk-header">
    <h1 class="kk-logo">Ken<em>Ken</em></h1>
    <div class="kk-divider"></div>
    <div class="kk-size-btns">
      <button class="kk-size-btn" data-size="4">4×4</button>
      <button class="kk-size-btn active" data-size="6">6×6</button>
    </div>
    <div class="kk-stats">
      <div class="kk-stat"><span class="kk-sv" id="stat-moves">0</span><span class="kk-sl">Moves</span></div>
      <div class="kk-stat"><span class="kk-sv" id="stat-errors">0</span><span class="kk-sl">Errors</span></div>
      <div class="kk-stat"><span class="kk-sv" id="stat-time">0:00</span><span class="kk-sl">Time</span></div>
      <div class="kk-stat"><span class="kk-sv" id="stat-filled">0%</span><span class="kk-sl">Filled</span></div>
    </div>
    <span class="kk-mode-badge normal" id="mode-badge">Normal</span>
  </header>
  <main class="kk-main">
    <section class="kk-grid-panel" id="grid-panel">
      <div class="kk-grid" id="puzzle-grid"></div>
      <div class="kk-win-overlay" id="win-overlay" data-testid="win-overlay">
        <div class="kk-win-title">Solved.</div>
        <div class="kk-win-sub" id="win-sub"></div>
        <button class="kk-win-btn" id="win-new-btn">New puzzle</button>
      </div>
    </section>
    <aside class="kk-sidebar">
      <div class="kk-sidebar-label">Console</div>
      <div class="kk-terminal" id="terminal-output" data-testid="terminal-output"></div>
      <div class="kk-input-row">
        <span class="kk-prompt-sym">›</span>
        <input class="kk-cmd-input" id="cmd-input" data-testid="cmd-input" placeholder="enter command..." autocomplete="off" spellcheck="false" />
      </div>
    </aside>
  </main>
  <footer class="kk-footer">
    <span class="kk-binding"><kbd>↑↓←→</kbd>Navigate</span>
    <span class="kk-binding"><kbd>1–6</kbd>Place</span>
    <span class="kk-binding"><kbd>Del</kbd>Clear</span>
    <span class="kk-binding"><kbd>P</kbd>Pencil</span>
    <span class="kk-binding"><kbd>H</kbd>Hint</span>
    <span class="kk-binding"><kbd>N</kbd>New</span>
    <span class="kk-binding"><kbd>set r c v</kbd>Move</span>
    <span class="kk-binding"><kbd>check</kbd>Validate</span>
    <span class="kk-binding"><kbd>solve</kbd>Auto-solve</span>
  </footer>
</div>
<script type="module">
import { KenKenEngine } from './src/engine/kenken-engine.js';
import { parseCommand } from './src/engine/command-parser.js';

const engine = new KenKenEngine();

let selected = null;
let pencilMode = false;
let pencilMarks = {};
let moves = 0;
let errors = 0;
let seconds = 0;
let won = false;
let timerInterval = null;
let currentSize = 6;
let cmdHistory = [];
let cmdIdx = -1;

const gridEl = document.getElementById('puzzle-grid');
const termEl = document.getElementById('terminal-output');
const inputEl = document.getElementById('cmd-input');
const winEl = document.getElementById('win-overlay');
const modeBadge = document.getElementById('mode-badge');
const winSub = document.getElementById('win-sub');

function emit(text, cls = 't-output') {
  const div = document.createElement('div');
  div.className = 'kk-tline ' + cls;
  div.textContent = text;
  termEl.appendChild(div);
  if (termEl.children.length > 160) termEl.removeChild(termEl.firstChild);
  const cur = termEl.querySelector('.kk-cursor');
  if (cur) cur.parentElement.remove();
  const curLine = document.createElement('div');
  curLine.className = 'kk-tline t-system';
  const curSpan = document.createElement('span');
  curSpan.className = 'kk-cursor';
  curLine.appendChild(curSpan);
  termEl.appendChild(curLine);
  termEl.scrollTop = termEl.scrollHeight;
}

function fmt(s) {
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

function updateStats() {
  document.getElementById('stat-moves').textContent = moves;
  document.getElementById('stat-errors').textContent = errors;
  document.getElementById('stat-errors').className = 'kk-sv' + (errors > 0 ? ' kk-sv-err' : '');
  const data = engine.getPuzzleData();
  const filled = data.grid.flat().filter(v => v > 0).length;
  document.getElementById('stat-filled').textContent = Math.round(filled / (currentSize * currentSize) * 100) + '%';
}

function startTimer() {
  if (timerInterval) clearInterval(timerInterval);
  seconds = 0;
  document.getElementById('stat-time').textContent = '0:00';
  timerInterval = setInterval(() => {
    seconds++;
    document.getElementById('stat-time').textContent = fmt(seconds);
  }, 1000);
}

function stopTimer() {
  if (timerInterval) clearInterval(timerInterval);
}

function cageLabel(cages, r, c) {
  const cage = cages.find(g => g.cells.some(x => x.row === r && x.col === c));
  if (!cage) return null;
  const tl = cage.cells.reduce((b, x) => (x.row < b.row || (x.row === b.row && x.col < b.col)) ? x : b, cage.cells[0]);
  if (tl.row !== r || tl.col !== c) return null;
  return cage.op ? `${cage.target}${cage.op}` : `${cage.target}`;
}

function cageBorders(cages, r, c) {
  const cage = cages.find(g => g.cells.some(x => x.row === r && x.col === c));
  if (!cage) return '';
  const has = (nr, nc) => cage.cells.some(x => x.row === nr && x.col === nc);
  return [
    !has(r-1, c) && 'cage-top',
    !has(r, c+1) && 'cage-right',
    !has(r+1, c) && 'cage-bottom',
    !has(r, c-1) && 'cage-left',
  ].filter(Boolean).join(' ');
}

function setSelected(r, c) {
  document.querySelectorAll('.kk-cell.selected').forEach(el => el.classList.remove('selected'));
  if (r === null) { selected = null; return; }
  selected = [r, c];
  const cell = document.querySelector(`[data-testid="cell-${r}-${c}"]`);
  if (cell) cell.classList.add('selected');
}

function flashCell(r, c, cls) {
  const cell = document.querySelector(`[data-testid="cell-${r}-${c}"]`);
  if (!cell) return;
  cell.classList.add(cls);
  setTimeout(() => cell.classList.remove(cls), 650);
}

function renderCell(r, c, val, cages) {
  const cell = document.querySelector(`[data-testid="cell-${r}-${c}"]`);
  if (!cell) return;
  const labelEl = cell.querySelector('.kk-cage-label');
  const existing = cell.querySelector('.kk-cell-body');
  if (existing) existing.remove();
  const body = document.createElement('div');
  body.className = 'kk-cell-body';
  body.style.cssText = 'display:flex;align-items:center;justify-content:center;width:100%;height:100%;position:relative;z-index:1';
  const key = `${r},${c}`;
  const pm = pencilMarks[key] || [];
  if (val > 0) {
    const span = document.createElement('span');
    span.className = 'kk-cell-val user';
    span.textContent = val;
    body.appendChild(span);
  } else if (pm.length > 0) {
    const grid = document.createElement('div');
    grid.className = 'kk-pencil-grid';
    for (let i = 1; i <= currentSize; i++) {
      const s = document.createElement('span');
      s.className = 'kk-pm' + (pm.includes(i) ? ' active' : '');
      s.textContent = pm.includes(i) ? i : '';
      grid.appendChild(s);
    }
    body.appendChild(grid);
  }
  cell.appendChild(body);
}

function buildGrid() {
  engine.newPuzzle(currentSize);
  pencilMarks = {};
  moves = 0; errors = 0; won = false;
  selected = null;
  winEl.classList.remove('visible');
  modeBadge.textContent = 'Normal';
  modeBadge.className = 'kk-mode-badge normal';
  startTimer();

  const data = engine.getPuzzleData();
  const cellPx = currentSize === 4 ? 72 : 56;
  gridEl.style.gridTemplateColumns = `repeat(${currentSize}, ${cellPx}px)`;
  gridEl.style.gridTemplateRows = `repeat(${currentSize}, ${cellPx}px)`;
  gridEl.innerHTML = '';

  for (let r = 0; r < currentSize; r++) {
    for (let c = 0; c < currentSize; c++) {
      const cell = document.createElement('div');
      cell.className = 'kk-cell';
      cell.setAttribute('data-testid', `cell-${r}-${c}`);
      cell.setAttribute('tabindex', '0');
      cell.style.width = cellPx + 'px';
      cell.style.height = cellPx + 'px';
      const borders = cageBorders(data.cages, r, c);
      if (borders) cell.className += ' ' + borders;
      const lbl = cageLabel(data.cages, r, c);
      if (lbl) {
        const lblEl = document.createElement('span');
        lblEl.className = 'kk-cage-label';
        lblEl.textContent = lbl;
        cell.appendChild(lblEl);
      }
      cell.addEventListener('click', () => {
        setSelected(r, c);
        cell.focus();
      });
      gridEl.appendChild(cell);
    }
  }

  updateStats();
  emit('─────────────────────────────────', 't-system');
  emit(`KenKen  ${currentSize}×${currentSize}  —  ${data.cages.length} cages loaded`, 't-info');
  emit('─────────────────────────────────', 't-system');
  emit("type 'help' for commands", 't-system');
}

function placeValue(r, c, v) {
  if (won) return;
  const res = engine.getMoveResult(r, c, v);
  moves++;
  if (res.ok) {
    engine.applyMove(r, c, v);
    renderCell(r, c, v, engine.getPuzzleData().cages);
    flashCell(r, c, 'flash-correct');
    emit(`  (${r+1},${c+1}) → ${v}  ✓`, 't-success');
    const check = engine.getCheckResult();
    if (check.complete) {
      stopTimer();
      won = true;
      winEl.classList.add('visible');
      winSub.textContent = `${currentSize}×${currentSize} · ${fmt(seconds)} · ${moves} moves · ${errors} errors`;
      emit('─────────────────────────────────', 't-success');
      emit('  Puzzle complete.', 't-success');
      emit('─────────────────────────────────', 't-success');
    }
  } else {
    errors++;
    flashCell(r, c, 'flash-error');
    emit(`  (${r+1},${c+1}) → ${v}  ✗  ${res.message}`, 't-error');
    if (res.code === 2) emit(`    row ${r+1} conflict`, 't-warn');
    if (res.code === 3) emit(`    col ${c+1} conflict`, 't-warn');
  }
  updateStats();
}

function runCommand(raw) {
  const c = raw.trim();
  if (!c) return;
  cmdHistory.unshift(c);
  cmdIdx = -1;
  emit(`› ${c}`, 't-prompt');

  if (c.toLowerCase() === 'help') {
    emit('Commands:', 't-info');
    ['set <row> <col> <val>  place a digit','clear <row> <col>      erase a cell','hint                   reveal one cell','check                  validate board','solve                  auto-solve','reset                  clear entries','new [4|6]              new puzzle','status                 board progress','pencil                 toggle pencil mode'].forEach(l => emit('  ' + l, 't-output'));
    return;
  }

  if (c.toLowerCase() === 'pencil') {
    pencilMode = !pencilMode;
    modeBadge.textContent = pencilMode ? 'Pencil' : 'Normal';
    modeBadge.className = 'kk-mode-badge ' + (pencilMode ? 'pencil' : 'normal');
    emit(`  pencil mode ${pencilMode ? 'on' : 'off'}`, 't-hint');
    return;
  }

  const parts = c.split(/\s+/);
  const op = parts[0].toLowerCase();

  if (op === 'set') {
    const r = parseInt(parts[1]) - 1, cv = parseInt(parts[2]) - 1, v = parseInt(parts[3]);
    if (isNaN(r) || isNaN(cv) || isNaN(v)) { emit('usage: set <row> <col> <val>', 't-error'); return; }
    placeValue(r, cv, v);
    return;
  }

  if (op === 'clear') {
    const r = parseInt(parts[1]) - 1, cv = parseInt(parts[2]) - 1;
    if (isNaN(r) || isNaN(cv)) { emit('usage: clear <row> <col>', 't-error'); return; }
    engine.clearCell(r, cv);
    renderCell(r, cv, 0, engine.getPuzzleData().cages);
    emit(`  (${r+1},${cv+1}) cleared`, 't-warn');
    return;
  }

  if (op === 'hint') {
    const h = engine.getHint();
    if (!h.found) { emit('  no empty cells', 't-info'); return; }
    emit(`  (${h.row+1},${h.col+1}) → try ${h.val}`, 't-hint');
    setSelected(h.row, h.col);
    return;
  }

  if (op === 'check') {
    const res = engine.getCheckResult();
    emit(`  ${res.filled}/${res.total} filled`, 't-info');
    if (res.rowErrors.length) emit(`  row errors: ${res.rowErrors.map(r => r+1).join(', ')}`, 't-error');
    if (res.colErrors.length) emit(`  col errors: ${res.colErrors.map(c => c+1).join(', ')}`, 't-error');
    if (res.cageErrors.length) emit(`  cage violations: ${res.cageErrors.length}`, 't-error');
    if (res.complete) emit('  ✓ valid and complete', 't-success');
    else if (res.filled === res.total) emit('  full but has errors', 't-warn');
    return;
  }

  if (op === 'solve') {
    engine.solvePuzzle();
    const data = engine.getPuzzleData();
    for (let r = 0; r < currentSize; r++)
      for (let cv = 0; cv < currentSize; cv++)
        renderCell(r, cv, data.grid[r][cv], data.cages);
    moves++;
    updateStats();
    emit('  ✓ solved', 't-success');
    stopTimer();
    won = true;
    winEl.classList.add('visible');
    winSub.textContent = `${currentSize}×${currentSize} · ${fmt(seconds)} · ${moves} moves · ${errors} errors`;
    return;
  }

  if (op === 'reset') {
    engine.resetBoard();
    const data = engine.getPuzzleData();
    for (let r = 0; r < currentSize; r++)
      for (let cv = 0; cv < currentSize; cv++)
        renderCell(r, cv, 0, data.cages);
    pencilMarks = {};
    emit('  board cleared', 't-warn');
    updateStats();
    return;
  }

  if (op === 'new') {
    const sz = parseInt(parts[1]);
    if (sz !== 4 && sz !== 6) { emit('  size must be 4 or 6', 't-error'); return; }
    currentSize = sz;
    document.querySelectorAll('.kk-size-btn').forEach(b => {
      b.classList.toggle('active', parseInt(b.dataset.size) === sz);
    });
    buildGrid();
    return;
  }

  if (op === 'status') {
    const data = engine.getPuzzleData();
    const filled = data.grid.flat().filter(v => v > 0).length;
    emit(`  ${filled}/${currentSize*currentSize} filled  ·  ${moves} moves  ·  ${errors} errors`, 't-info');
    emit(`  ${fmt(seconds)}  ·  mode: ${pencilMode ? 'pencil' : 'normal'}`, 't-info');
    return;
  }

  emit(`  unknown command '${op}' — type 'help'`, 't-error');
}

document.querySelectorAll('.kk-size-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    currentSize = parseInt(btn.dataset.size);
    document.querySelectorAll('.kk-size-btn').forEach(b => b.classList.toggle('active', b === btn));
    buildGrid();
  });
});

document.getElementById('win-new-btn').addEventListener('click', () => {
  winEl.classList.remove('visible');
  buildGrid();
});

inputEl.addEventListener('keydown', e => {
  if (e.key === 'Enter') { runCommand(inputEl.value); inputEl.value = ''; }
  else if (e.key === 'ArrowUp') {
    const ni = Math.min(cmdIdx + 1, cmdHistory.length - 1);
    if (cmdHistory[ni]) { inputEl.value = cmdHistory[ni]; cmdIdx = ni; }
    e.preventDefault();
  } else if (e.key === 'ArrowDown') {
    const ni = Math.max(cmdIdx - 1, -1);
    inputEl.value = ni >= 0 ? cmdHistory[ni] : '';
    cmdIdx = ni;
    e.preventDefault();
  }
});

window.addEventListener('keydown', e => {
  if (document.activeElement === inputEl) return;
  if (document.activeElement && document.activeElement.tagName === 'INPUT') return;
  if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.key)) {
    e.preventDefault();
    if (!selected) { setSelected(0, 0); return; }
    const [r, c] = selected;
    if (e.key === 'ArrowUp')    setSelected(Math.max(0, r-1), c);
    else if (e.key === 'ArrowDown')  setSelected(Math.min(currentSize-1, r+1), c);
    else if (e.key === 'ArrowLeft')  setSelected(r, Math.max(0, c-1));
    else if (e.key === 'ArrowRight') setSelected(r, Math.min(currentSize-1, c+1));
    return;
  }
  if (e.key === 'Escape') { setSelected(null, null); return; }
  const [r, c] = selected || [0, 0];
  if (false) {}
  else if (e.key === 'p' || e.key === 'P') { runCommand('pencil'); }
  else if (e.key === 'h' || e.key === 'H') { runCommand('hint'); }
  else if (e.key === 'n' || e.key === 'N') { buildGrid(); }
  else if ((e.key === 'Delete' || e.key === 'Backspace') && selected) {
    runCommand(`clear ${r+1} ${c+1}`);
  } else if (/^[1-6]$/.test(e.key) && selected) {
    const v = parseInt(e.key);
    if (v <= currentSize) {
      if (pencilMode) {
        const key = `${r},${c}`;
        const pm = new Set(pencilMarks[key] || []);
        pm.has(v) ? pm.delete(v) : pm.add(v);
        pencilMarks[key] = [...pm];
        renderCell(r, c, engine.getPuzzleData().grid[r][c], engine.getPuzzleData().cages);
      } else {
        placeValue(r, c, v);
      }
    }
  }
});

buildGrid();
</script>
</body>
</html>



HTMLEOF
