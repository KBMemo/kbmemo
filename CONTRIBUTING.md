# Contributing to KBMemo

Thank you for contributing to KBMemo. Small, focused changes with tests and clear intent
are easiest to review.

## Before you start

Read [AGENTS.md](AGENTS.md) for the application boundaries and local conventions. Use an
issue or discussion to align on changes that alter persistent data, public APIs,
authentication, or the AsciiDoc editor model.

For a local development environment:

```bash
bundle install
npm ci
bin/rails credentials:edit
bin/rails db:prepare
bin/dev
```

Set `db.development` and `db.test` following
[`config/credentials/db.example.yml`](config/credentials/db.example.yml). Never commit
credentials, API tokens, or production data.

## Validation

Run the narrowest relevant checks while developing, then run the full suite before opening
a pull request when practical.

```bash
bin/rails test test/path/to/test.rb
npx vitest run packages/adoc-kbmemo
npm run check:utility-compat
bin/ci
```

Changes to Slim, CSS, or Stimulus should follow the component and accessibility guidance
in `AGENTS.md`. Changes to `packages/adoc-*` also need their package tests and build
checked.

## Pull requests

Keep each pull request focused. Describe the user-visible behavior, tests run, and any
follow-up work. Add or update tests for behavioral changes, and update documentation when
you change a public API, configuration contract, or operational procedure.

Do not include unrelated formatting, generated assets, or private environment details.

## Security reports

Do not open public issues for suspected vulnerabilities. Follow
[SECURITY.md](SECURITY.md) instead.
