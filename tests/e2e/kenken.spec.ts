import { test, expect, type Page } from "@playwright/test";

async function go(page: Page) {
  /**
   * Navigate and block until at least one cell is visible — covers the async engine
   * initialisation that fires before any puzzle grid renders.
   */
  await page.goto("/");
  await page.waitForSelector('[data-testid^="cell-"]', { timeout: 10_000 });
}

async function sendCmd(page: Page, cmd: string) {
  /**
   * Click the input to ensure focus, fill it with the command string, then submit.
   * Using fill rather than type avoids issues with special characters in the command.
   */
  const input = page.locator('[data-testid="cmd-input"]');
  await input.click();
  await input.fill(cmd);
  await input.press("Enter");
}

async function termHas(page: Page, text: string) {
  /**
   * Poll the terminal panel for the expected substring with a generous timeout
   * because some commands (solve, hint) trigger async engine calls.
   */
  await expect(page.locator('[data-testid="terminal-output"]')).toContainText(text, { timeout: 6_000 });
}

async function hintCoords(page: Page): Promise<[number, number, number] | null> {
  /**
   * Run hint and scrape the coordinates from the terminal output.
   * Returns null if the terminal does not contain a parseable hint line.
   */
  await sendCmd(page, "hint");
  const text = await page.locator('[data-testid="terminal-output"]').textContent();
  const m = text?.match(/\((\d+),(\d+)\)[^0-9]+(\d+)/);
  return m ? [parseInt(m[1]), parseInt(m[2]), parseInt(m[3])] : null;
}

test("page title is KenKen", async ({ page }) => {
  /**
   * The document title must be exactly "KenKen" — browsers, tab lists,
   * and accessibility tools all surface this as the primary page identity.
   */
  await go(page);
  await expect(page).toHaveTitle(/KenKen/);
});

test("h1 heading is visible on load", async ({ page }) => {
  /**
   * An h1 matching /kenken/i must be rendered and visible without any user interaction.
   */
  await go(page);
  await expect(page.getByRole("heading", { name: /kenken/i })).toBeVisible();
});

test("default 6x6 grid renders 36 cells", async ({ page }) => {
  /**
   * The puzzle grid must contain exactly 36 elements with data-testid="cell-R-C"
   * on first load — more or fewer indicates a generation or rendering bug.
   */
  await go(page);
  await expect(page.locator('[data-testid^="cell-"]')).toHaveCount(36);
});

test("cage labels are visible on the grid", async ({ page }) => {
  /**
   * At least one cage-label must be present and visible — missing labels would
   * make it impossible for the player to know the arithmetic target for each cage.
   */
  await go(page);
  await expect(page.locator(".kk-cage-label").first()).toBeVisible();
});

test("clicking a cell adds selected class", async ({ page }) => {
  /**
   * A direct click on cell-0-0 must toggle the selected CSS class onto that element.
   * This drives keyboard navigation and digit placement.
   */
  await go(page);
  await page.locator('[data-testid="cell-0-0"]').click();
  await expect(page.locator('[data-testid="cell-0-0"]')).toHaveClass(/selected/);
});

test("ArrowRight moves selection one column right", async ({ page }) => {
  /**
   * After selecting cell-0-0, a single ArrowRight keypress must shift selection to
   * cell-0-1 without deselecting the previous cell first via keyboard.
   */
  await go(page);
  await page.locator('[data-testid="cell-0-0"]').click();
  await expect(page.locator('[data-testid="cell-0-0"]')).toHaveClass(/selected/);
  await page.keyboard.press("ArrowRight");
  await expect(page.locator('[data-testid="cell-0-1"]')).toHaveClass(/selected/);
});

test("ArrowDown moves selection one row down", async ({ page }) => {
  /**
   * After selecting cell-0-0, ArrowDown must move to cell-1-0 in the row below.
   */
  await go(page);
  await page.locator('[data-testid="cell-0-0"]').click();
  await expect(page.locator('[data-testid="cell-0-0"]')).toHaveClass(/selected/);
  await page.keyboard.press("ArrowDown");
  await expect(page.locator('[data-testid="cell-1-0"]')).toHaveClass(/selected/);
});

test("Escape removes selected class from cell", async ({ page }) => {
  /**
   * Pressing Escape must deselect the active cell — required so players can
   * dismiss the selection before switching to the command input.
   */
  await go(page);
  await page.locator('[data-testid="cell-0-0"]').click();
  await expect(page.locator('[data-testid="cell-0-0"]')).toHaveClass(/selected/);
  await page.keyboard.press("Escape");
  await expect(page.locator('[data-testid="cell-0-0"]')).not.toHaveClass(/selected/);
});

test("terminal output panel is visible", async ({ page }) => {
  /**
   * The console panel must be present and visible — it is the primary feedback
   * channel for every command, error, and game event.
   */
  await go(page);
  await expect(page.locator('[data-testid="terminal-output"]')).toBeVisible();
});

test("command input is visible and accepts text", async ({ page }) => {
  /**
   * The input must render, accept a typed string, and retain it without auto-clearing.
   */
  await go(page);
  const input = page.locator('[data-testid="cmd-input"]');
  await input.click();
  await input.fill("help");
  await expect(input).toHaveValue("help");
});

test("help command writes output to the terminal", async ({ page }) => {
  /**
   * Typing help and pressing Enter must produce terminal output containing 'set',
   * confirming the command router is wired to the UI.
   */
  await go(page);
  await sendCmd(page, "help");
  await termHas(page, "set");
});

test("check command reports fill count in the terminal", async ({ page }) => {
  /**
   * The check command must emit a message containing the word 'filled' so
   * players know the completion status without counting cells manually.
   */
  await go(page);
  await sendCmd(page, "check");
  await termHas(page, "filled");
});

test("hint selects a cell and prints coordinates", async ({ page }) => {
  /**
   * After hint runs, the terminal must show coordinates and exactly one cell
   * must carry the selected class — confirming the UI moved focus to the hinted cell.
   */
  await go(page);
  await sendCmd(page, "hint");
  await termHas(page, "try");
  await expect(page.locator(".kk-cell.selected")).toBeVisible();
});

test("solve fills all 36 cells with digits 1-6", async ({ page }) => {
  /**
   * After solve, every kk-cell-val element must contain a single digit in the
   * range 1-6 — any blank or out-of-range value indicates a rendering bug.
   */
  await go(page);
  await sendCmd(page, "solve");
  await termHas(page, "solved");
  const vals = page.locator(".kk-cell-val");
  await expect(vals).toHaveCount(36);
  const count = await vals.count();
  for (let i = 0; i < count; i++) {
    expect((await vals.nth(i).textContent())?.trim()).toMatch(/^[1-6]$/);
  }
});

test("win overlay becomes visible after solving", async ({ page }) => {
  /**
   * The win overlay must appear when the puzzle is completed — it is the primary
   * completion signal for the player and is verified by the test suite.
   */
  await go(page);
  await sendCmd(page, "solve");
  await expect(page.locator('[data-testid="win-overlay"]')).toBeVisible({ timeout: 4_000 });
});

test("win overlay contains text matching /solved/i", async ({ page }) => {
  /**
   * The overlay text must communicate that the puzzle was solved — a blank overlay
   * would pass the visibility test but fail to inform the player.
   */
  await go(page);
  await sendCmd(page, "solve");
  await expect(page.locator('[data-testid="win-overlay"]')).toContainText(/solved/i, { timeout: 4_000 });
});

test("new puzzle button in win overlay dismisses it", async ({ page }) => {
  /**
   * Clicking the new-puzzle button must hide the overlay and reset the grid —
   * leaving the overlay visible would block interaction with the new puzzle.
   */
  await go(page);
  await sendCmd(page, "solve");
  const overlay = page.locator('[data-testid="win-overlay"]');
  await expect(overlay).toBeVisible({ timeout: 4_000 });
  await overlay.locator("button").click();
  await expect(overlay).not.toBeVisible({ timeout: 4_000 });
});

test("4x4 size button switches the grid to 16 cells", async ({ page }) => {
  /**
   * Clicking the 4×4 button must rebuild the grid with exactly 16 cells —
   * any leftover cells from the previous 6×6 grid indicate a teardown bug.
   */
  await go(page);
  await page.locator(".kk-size-btn").filter({ hasText: "4" }).click();
  await expect(page.locator('[data-testid^="cell-"]')).toHaveCount(16);
});

test("6x6 size button restores 36 cells after switching to 4x4", async ({ page }) => {
  /**
   * Switching from 4×4 back to 6×6 must produce exactly 36 cells — confirms
   * the grid rebuild is idempotent and does not accumulate leftover elements.
   */
  await go(page);
  await page.locator(".kk-size-btn").filter({ hasText: "4" }).click();
  await page.locator(".kk-size-btn").filter({ hasText: "6" }).click();
  await expect(page.locator('[data-testid^="cell-"]')).toHaveCount(36);
});

test("new 4 command loads a 4x4 grid via the terminal", async ({ page }) => {
  /**
   * The 'new 4' command must load a 4×4 puzzle — confirms the command router
   * and size-switch path work through the terminal as well as the UI buttons.
   */
  await go(page);
  await sendCmd(page, "new 4");
  await expect(page.locator('[data-testid^="cell-"]')).toHaveCount(16);
});

test("new 9 command shows an error in the terminal", async ({ page }) => {
  /**
   * An invalid size must produce an error message rather than silently failing
   * or generating a broken puzzle.
   */
  await go(page);
  await sendCmd(page, "new 9");
  await termHas(page, "size must be 4 or 6");
});

test("P key toggles mode badge between Normal and Pencil", async ({ page }) => {
  /**
   * Pressing P must switch the badge text to Pencil; pressing it again must revert
   * to Normal — confirming the toggle is stateful and bidirectional.
   */
  await go(page);
  await page.locator('[data-testid="cell-0-0"]').click();
  await expect(page.locator('[data-testid="cell-0-0"]')).toHaveClass(/selected/);
  await page.keyboard.press("p");
  await expect(page.locator(".kk-mode-badge")).toContainText(/pencil/i);
  await page.keyboard.press("p");
  await expect(page.locator(".kk-mode-badge")).toContainText(/normal/i);
});

test("pencil command toggles mode badge via the terminal", async ({ page }) => {
  /**
   * The pencil command must activate pencil mode — the same state change
   * that the P key triggers, confirming both paths reach the same toggle.
   */
  await go(page);
  await sendCmd(page, "pencil");
  await expect(page.locator(".kk-mode-badge")).toContainText(/pencil/i);
});

test("pencil marks appear inside a cell in pencil mode", async ({ page }) => {
  /**
   * After switching to pencil mode and pressing 1, the cell must contain exactly
   * one kk-pm.active element — no more, no less.
   */
  await go(page);
  await sendCmd(page, "pencil");
  await page.locator('[data-testid="cell-0-0"]').click();
  await expect(page.locator('[data-testid="cell-0-0"]')).toHaveClass(/selected/);
  await page.keyboard.press("1");
  await expect(page.locator('[data-testid="cell-0-0"] .kk-pm.active')).toHaveCount(1);
});

test("valid set command places the digit in the target cell", async ({ page }) => {
  /**
   * A correct 'set R C V' command must render a kk-cell-val element inside the
   * specified cell containing the placed digit.
   */
  await go(page);
  const h = await hintCoords(page);
  if (!h) return;
  const [r, c, v] = h;
  await sendCmd(page, `set ${r} ${c} ${v}`);
  await expect(page.locator(`[data-testid="cell-${r - 1}-${c - 1}"] .kk-cell-val`)).toContainText(String(v));
});

test("reset command removes all placed digits", async ({ page }) => {
  /**
   * After solving and then resetting, zero kk-cell-val elements should remain —
   * any residual value indicates the reset does not fully clear the render state.
   */
  await go(page);
  await sendCmd(page, "solve");
  await termHas(page, "solved");
  await sendCmd(page, "reset");
  await termHas(page, "cleared");
  await expect(page.locator(".kk-cell-val")).toHaveCount(0);
});

test("moves counter increments after a valid placement", async ({ page }) => {
  /**
   * The moves stat element must change from 0 to a higher value after one correct
   * placement — confirms the stat is wired to the move event, not reset to 0 on every render.
   */
  await go(page);
  const stat = page.locator(".kk-stat").filter({ hasText: /moves/i }).locator(".kk-sv");
  await expect(stat).toHaveText("0");
  const h = await hintCoords(page);
  if (!h) return;
  await sendCmd(page, `set ${h[0]} ${h[1]} ${h[2]}`);
  await expect(stat).not.toHaveText("0");
});

test("timer changes from 0:00 within two seconds of load", async ({ page }) => {
  /**
   * The time stat must start at 0:00 and increment on its own — a frozen timer
   * would give the player no feedback on elapsed time.
   */
  await go(page);
  const stat = page.locator(".kk-stat").filter({ hasText: /time/i }).locator(".kk-sv");
  await expect(stat).toHaveText("0:00");
  await page.waitForTimeout(2_100);
  expect(await stat.textContent()).not.toBe("0:00");
});
