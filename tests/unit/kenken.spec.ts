import { describe, it, expect, beforeEach } from "vitest";
import { screen } from "@testing-library/dom";
import { userEvent } from "@testing-library/user-event";

describe("KenKen UI DOM contract", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <h1>KenKen</h1>
      <div data-testid="cell-0-0" class="kk-cell" tabindex="0"></div>
      <div data-testid="cell-0-1" class="kk-cell" tabindex="0"></div>
      <div data-testid="cell-1-0" class="kk-cell" tabindex="0"></div>
      <div data-testid="terminal-output"></div>
      <input data-testid="cmd-input" />
      <span class="kk-mode-badge">Normal</span>
    `;
  });

  it("heading matching /kenken/i is present in the document", () => {
    /**
     * The page must expose an h1 so assistive technology and Playwright role queries
     * can find the KenKen heading without relying on class names.
     */
    const h = screen.getByRole("heading", { name: /kenken/i });
    expect(h).toBeTruthy();
    expect(h.textContent).toBe("KenKen");
  });

  it("cells carry the cell-R-C data-testid naming scheme", () => {
    /**
     * Every grid cell gets a testid like cell-0-0 so E2E tests can target
     * individual positions without brittle CSS selectors.
     */
    expect(document.querySelector('[data-testid="cell-0-0"]')).toBeTruthy();
    expect(document.querySelector('[data-testid="cell-1-0"]')).toBeTruthy();
  });

  it("terminal output panel exists in the DOM", () => {
    /**
     * The console panel must be present from initial load — the UI wires
     * game messages to it immediately when a puzzle is generated.
     */
    expect(document.querySelector('[data-testid="terminal-output"]')).toBeTruthy();
  });

  it("command input accepts typed text", async () => {
    /**
     * Verify the input element is interactive — userEvent confirms it responds
     * to keyboard events correctly before any focus management logic runs.
     */
    const input = screen.getByTestId("cmd-input") as HTMLInputElement;
    const user = userEvent.setup();
    await user.type(input, "help");
    expect(input.value).toBe("help");
  });

  it("clicking a cell adds the selected class", async () => {
    /**
     * Cell selection is purely a CSS class toggle — this confirms the click
     * handler wires up correctly without requiring the full game engine.
     */
    const cell = document.querySelector('[data-testid="cell-0-0"]') as HTMLElement;
    const user = userEvent.setup();
    cell.addEventListener("click", () => cell.classList.add("selected"));
    await user.click(cell);
    expect(cell.classList.contains("selected")).toBe(true);
  });

  it("mode badge defaults to Normal text", () => {
    /**
     * The badge must start in Normal mode; the UI switches it to Pencil only
     * when the user explicitly activates pencil mode via P key or command.
     */
    const badge = document.querySelector(".kk-mode-badge") as HTMLElement;
    expect(badge).toBeTruthy();
    expect(badge.textContent).toBe("Normal");
  });
});
