# KenKen task test suite

Unit tests (Vitest + Testing Library) and E2E tests (Playwright). Dependencies and the Playwright browser are installed in `environment/Dockerfile` at image build time so the verifier does not need internet access at runtime.

## Layout

- `unit/` — Vitest specs testing DOM contract
- `e2e/` — Playwright specs testing the full UI served at http://localhost:3000
- `fixtures/` — Static fallback page for local development reference

## Commands

```bash
npm run test       # Unit tests
npm run test:e2e   # E2E tests (starts webServer automatically)
```
