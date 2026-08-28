# Translations — contributor guide

GPU Rental Kit is documented in multiple languages. The English
[`README.md`](../README.md) is the source of truth and the GitHub landing
page. Translations live next to it as `README.<code>.md` files and are
tracked in the language registry ([`docs/languages.env`](languages.env)).

| Language | File | Status |
|---|---|---|
| English | [`README.md`](../README.md) | complete (source of truth) |
| Vietnamese | [`README.vi.md`](../README.vi.md) | complete |
| Simplified Chinese | [`README.zh-CN.md`](../README.zh-CN.md) | complete |

---

## How languages are named

Use standard [BCP 47](https://en.wikipedia.org/wiki/IETF_language_tag)
language identifiers:

| Code | Language |
|---|---|
| `en` | English |
| `vi` | Vietnamese |
| `zh-CN` | Chinese (Simplified) |
| `zh-TW` | Chinese (Traditional) |
| `ja` | Japanese |
| `ko` | Korean |
| `fr` | French |
| `de` | German |
| `es` | Spanish |
| `pt-BR` | Portuguese (Brazil) |
| `id` | Indonesian |
| `th` | Thai |
| `ar` | Arabic (right-to-left) |

Do **not** use legacy identifiers such as `vn`, `cn`, `jp`, or `kr`.

Regional variants are written with a hyphen: `zh-CN`, `zh-TW`, `pt-BR`.
Simplified and Traditional Chinese are **separate** translations — never
share one Chinese file for both.

---

## How to add a new language

Adding a language requires **no application code changes**. The workflow:

1. **Create the translation file** — copy the structure from
   [`docs/TRANSLATION_TEMPLATE.md`](TRANSLATION_TEMPLATE.md) (or start from
   the current English `README.md`) and translate it.
2. **Register the language** — add one line to `docs/languages.env`:

   ```bash
   "ja|Japanese|日本語|🇯🇵|README.ja.md|in-progress|ltr"
   ```

   Fields, in order: `code | English name | native name | flag | path |
   status | direction`.
3. **Update the language selector** — regenerate the selector row and paste
   it into **every** README (including the English one):

   ```bash
   bash docs/lang-selector.sh
   ```

   Only languages with status `complete` or `partial` appear in the
   selector, so in-progress translations stay hidden until they are ready.
4. **Validate** — run the documentation language tests:

   ```bash
   bash test/tests/test_documentation_languages.sh
   ```

   The same test runs automatically in the full suite
   (`./test/run_all.sh local`) and in CI.
5. **Open a pull request** describing the new language.

That is the whole workflow — e.g. adding Japanese is: create
`README.ja.md`, translate it, add the `ja` line to the registry, refresh
the selector, run the tests, submit the PR.

---

## How to update an existing translation

1. Compare the translation against the English `README.md`.
2. Translate the new or changed sections, keeping all commands, filenames,
   environment variables, and URLs identical.
3. Update the translation's source revision so it is no longer flagged as
   stale. See [Keeping translations in sync](#keeping-translations-in-sync).

---

## Translation status

| Status | Meaning | Shown in selector? |
|---|---|---|
| `complete` | Fully translated and reviewed | yes |
| `partial` | Usable but some sections untranslated | yes |
| `outdated` | Source README changed; needs review | no |
| `in-progress` | Being translated, not ready | no |

Never mark a translation `complete` when it is missing sections or commands.
Prefer `partial` so users can still benefit while contributors finish it.

---

## Keeping translations in sync

The test suite (`test/tests/test_documentation_languages.sh`) enforces
structural parity automatically:

- every registered language file exists;
- every README carries the same language selector as the registry;
- no broken relative links or image references;
- translations keep **every non-comment command** from the English README;
- translations keep **every environment variable and technical identifier**
  (e.g. `GPU_IDS`, `CUDA_VISIBLE_DEVICES`, `model-run`);
- `##` section counts match the English README (missing sections fail);
- code-fence counts match (missing code blocks fail).

### Source revisions

Every README carries a machine-readable marker near the top:

```html
<!-- SOURCE-REVISION: 2641105185 -->
```

The value is a content checksum of the English `README.md` (with the marker
line itself excluded, so the value is stable). When the English README
changes, its checksum changes, and the test prints a warning for every
translation that has not been re-reviewed:

```text
⚠ README.vi.md: translation may be outdated ... — review and update SOURCE-REVISION
```

Stale translations are a **warning**, not a test failure — but please do not
ship a translation that has not been reviewed against the current English
README. When you finish reviewing, update the translation's marker to the
value printed by the warning (or run the test to see the expected value).

The English README's own marker must always be current; the test warns if
it is not.

---

## What must never be translated

Translations adapt prose, but the following are preserved **verbatim**:

- **Technical identifiers:** GPU, VRAM, CUDA, NVIDIA, Docker, llama.cpp,
  Ollama, vLLM, PyTorch, Hugging Face, OpenAI, API, SSH, Linux, Windows,
  macOS;
- **Environment variables:** `GPU_IDS`, `GPU_MODE`,
  `CUDA_VISIBLE_DEVICES`, `NVIDIA_VISIBLE_DEVICES`, and any other
  `UPPER_SNAKE_CASE` name;
- **Commands and flags:** `bootstrap.sh`, `model-run`, `gpu-status`,
  `gpu-test`, `ai-start`, `--gpus all`, and every code block;
- **Filenames and paths:** `~/ai/models/...`, `docker/compose.yml`,
  `config/defaults.env`;
- **URLs and links:** the repository URL, release links, `localhost`
  endpoints.

User-visible prose (descriptions, warnings, table labels, headings) is
translated. Code comments inside command blocks may be translated too, but
the commands themselves must stay byte-identical.

### Project positioning

Translations must keep the project's primary message intact: GPU Rental Kit
**saves time when renting and setting up GPU servers** — the workflow is
**RENT → INSTALL → TEST → RUN**. Multi-GPU is an important feature, not the
whole project. Keep this framing consistent in every language.

### Platform roles

Be precise about where things run:

- **Linux** — the remote GPU server environment (`bootstrap.sh --remote-gpu`);
- **macOS** — development/client machine only;
- **Windows** — development/client machine with `bootstrap.ps1`, connecting
  to a remote GPU server over SSH.

Never claim the Linux GPU bootstrap runs natively on macOS or Windows.

---

## Right-to-left languages

The registry supports `direction: rtl` for future Arabic/Hebrew support.
Markdown on GitHub renders LTR by default; contributors adding an RTL
language should keep the language selector row LTR and apply RTL direction
only to the translated prose, using Unicode bidirectional controls where
needed.

---

## Validation recap

```bash
# Single test
bash test/tests/test_documentation_languages.sh

# Full local suite (includes the test above, consistency, mocks, fresh copy)
./test/run_all.sh local
```

CI runs the full local suite on every push; a translation that is
registered but missing, linked but missing, or missing required commands
fails CI.
