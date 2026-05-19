# Prompt-engineer brief: Penny refinement modes

This document is the full context for a prompt engineer brought in to design
the system prompts that power Penny's refinement picker. It's deliberately
self-contained — assume the reader has not seen the codebase.

If you are that prompt engineer: read this top to bottom before writing
anything. The architecture and constraints are non-negotiable; the prompts
themselves are entirely yours to redesign.

---

## 1. What Penny is

Penny is a macOS menu-bar app that gives the user two shortcuts on the
Right Option key:

- **Hold Right Option** → dictate. Local Whisper transcription. *Not your
  concern.*
- **Double-tap Right Option** → **refine**. *This is what you're working on.*

When the user double-taps Right Option, a small picker appears with up to
ten refinement modes. The user clicks one (or presses its digit shortcut).
Whatever text was selected in the user's frontmost app at the moment of
trigger is sent through an LLM with one of your system prompts, and the
result is pasted back **in place of the selection**.

This last point is the most important constraint in this entire document.
**Your output is the user's text.** Anything you produce replaces and
destroys what they had. There is no "undo" beyond the system clipboard, and
there is no review step.

---

## 2. End-to-end flow

```
User selects text in any macOS app
         │
         ▼
Double-taps Right Option
         │
         ▼
Native daemon copies the selection (via Accessibility API or ⌘C)
         │
         ▼
Picker overlay appears next to cursor; user picks a mode
         │
         ▼
Native daemon spawns a Python subprocess with:
   • the user's text as a JSON `text` field on stdin
   • the chosen mode's id
         │
         ▼
Python helper looks up the mode's `prompt` (= your system prompt) in
~/.penny/modes.json
         │
         ▼
Python helper sends one chat completion request to the configured provider
(Anthropic / OpenAI / Gemini):
   • System message  = the mode's prompt
   • User message    = the selected text, verbatim
   • max_tokens, timeout, etc. from config
         │
         ▼
Python helper prints the model response to stdout (JSON)
         │
         ▼
Native daemon parses, then PASTES the model's output verbatim into the
user's frontmost app, replacing their original selection.
```

You write the **system message** for each mode. That's the entire surface
of your job.

---

## 3. Modes today

The current shipping set:

| id | Name | Detail (shown in picker) | Intent |
|----|------|--------------------------|--------|
| 1  | Spelling only | spelling fixes, nothing else | Fix misspellings (incl. stretched typos), change nothing else |
| 2  | Grammar | grammar, punctuation + spelling | Fix mechanical correctness (spelling, grammar, punctuation, capitalisation); preserve phrasing and voice |
| 3  | Improve Writing | tighter, clearer · same meaning | Cut filler, sharpen phrasing, preserve voice and meaning |
| 4  | Slack | succinct · warm · lowercase | Rewrite as a Slack message in a specific person's voice (lowercase, no periods, warm, emoji-sparing) |
| 5  | Email | polished · ends with cheers | Rewrite as a warm but polished email body that ends with "Cheers," |
| 6  | Report | notion-formatted · layered | Rewrite as a Notion-formatted report with headings, emoji section markers, callouts, toggles |
| 7  | Bullet Points | scannable · discrete ideas | Convert prose to bullet points |
| 8  | Improve Prompt | rewrite for an LLM | Rewrite the user's input as a better prompt to send to *another* LLM |
| 9  | Custom… | (user types a one-off instruction) | User-provided system prompt for this run |
| 0  | Cancel | (no-op) | User backed out of the picker |

The current prompts live in [`config/modes.default.json`](../config/modes.default.json).
Read them before redesigning. **They are the starting point, not the
destination.** They are good enough to ship but not good enough to be proud
of, and they have failure modes documented below.

---

## 4. Hard constraints (every mode, every time)

These are non-negotiable behaviours every mode's prompt must guarantee.
A regression on any of them is a P0 bug because it overwrites the user's
text with something nonsensical.

### 4.1 The output is a paste

Your output is pasted directly in place of the user's selection.
Therefore:

- **No preamble.** No "Here is the rewritten version:", no "Sure, I can
  help with that.", no "Improved Prompt:" labels, no Markdown code
  fences, no quotation marks wrapping the result.
- **No commentary.** No "Note: I assumed …", no "I made the following
  changes:".
- **No refusal.** If the model decides the input doesn't need editing,
  doesn't fit the mode, or can't be improved, it must return the input
  **exactly unchanged** rather than explain why.
- **No questions.** Never ask the user for more text, more context, or
  clarification. The model gets one shot and must use what it has.

If the output is anything other than the intended replacement text, the
user's selection is destroyed.

### 4.2 Never make things up

This is the hill to die on. The user's selection is the ground truth.

- **Don't add facts**, claims, examples, numbers, names, dates, or
  references that aren't in the source.
- **Don't fill in placeholders** with plausible-sounding content. If
  context is missing, leave it missing or use an explicit `[bracketed
  placeholder]`.
- **Don't infer the user's intent** beyond what they actually wrote.
  "Looks like you meant to say X" — no. Only act on what was clearly,
  unambiguously written.

The principle: **reduce ambiguity only when certainty exists**. If you
can confidently fix a misspelling, do it. If you'd be guessing at the
user's intended word, leave it alone.

### 4.3 The "no change required" path

If a mode genuinely can't or shouldn't change the input — because it's
already correct, because it's out of scope for the mode, because the
input is too ambiguous to act on safely — the correct behaviour is to
**return the input verbatim, byte for byte**.

Penny detects when the model output equals the input and shows a small
"No change required" toast instead of pasting (no point pasting identical
text). The detection is exact-match; even a trailing newline difference
counts as a change. Your prompts must make this byte-equality possible
when no edit is warranted.

**Detection rule** (already handled by the engineering side, listed
here so you know what you're optimising for):

```
norm(s) = s.trimmingCharacters(in: .whitespacesAndNewlines)

if norm(refined) == norm(original):
    show toast: "✓ No change needed"
    skip paste entirely  (the user's selection stays as-is)
else:
    paste refined
```

The toast is the existing small bottom-centre HUD used for "✓ Pasted",
shown for 1.2 s, accent-tinted. The user's selection is **not** touched
in this branch. From your side, the only obligation is: when no edit is
warranted, return the input **with no added whitespace, no rewrapping,
no normalisation of line endings**. The trim above is generous, but
preserving the input character-for-character is safest.

### 4.4 Don't impose your voice

Every editing mode (1, 2, 3) must preserve the user's voice, register,
and tone. Penny is editing the user's words, not the model's.

- Casual stays casual; formal stays formal.
- Lowercase-throughout stays lowercase-throughout (Slack-style).
- Hedges and filler the user clearly intended (e.g. ending a Slack
  message with "haha" or a 🙏) stay.
- Bullet points stay bullet points unless the mode is explicitly
  converting away from them.

### 4.5 Modes that fundamentally rewrite (4, 5, 6, 7, 8)

These modes apply a *target style*, not the user's. Slack mode produces
a Slack message regardless of what the user gave it. The "preserve voice"
rule above does not apply to these; what applies instead is that the
output must conform precisely to the mode's documented style rules.

The exception: the **meaning** must be preserved. If the user wrote
"the deploy is broken", Slack mode rewrites it warmly but must not
change it to "the deploy is fine".

---

## 5. Failure modes observed in the wild

Real examples from user history. Your redesign must not regress on any
of these.

### 5.1 Refusal pasted on top of selection

Input (mode 3, Improve Writing): `What is the biggest building in the world?`

Bad output (real, from an earlier prompt):
> This isn't text that needs editing — it's a question. I can only help
> by rewriting text you provide to make it clearer and more concise.
> Please share a piece of writing you'd like me to edit.

This was pasted **on top of** the user's text in their app. Destroyed
their work. **This is the single worst class of bug Penny has** — any
mode prompt that tempts the model to refuse must be rewritten to either
attempt an edit or return the input verbatim.

### 5.2 Stretched typos ignored

Input (mode 1, Spelling only): `How many chickensssssssssssss can a chicken chicken when it has two eggs and a chicken?`

Bad output: same text, unchanged.

Expected: `How many chickens can a chicken chicken when it has two eggs
and a chicken?`

The model assumed the repeated `s` was intentional emphasis. Spelling
mode must explicitly include stretched-letter typos in scope.

### 5.3 Improve Prompt adding `**Improved Prompt:**` label

The earlier prompt for mode 8 produced two sections labelled
`**Improved Prompt:**` and `**What Changed & Why:**`, both of which got
pasted into the user's text field. Output contract: just the rewritten
prompt, no headers, no notes.

### 5.4 Vague-input expansion in Improve Prompt

Input (mode 8): `make this app look more macbook like`

Bad output: a 12-bullet specification with invented Big Sur version
constraints, specific font choices (SF Pro), CSS frameworks, etc.

Expected: a short, scoped rewrite using bracketed placeholders for the
unknowns. The user didn't ask for SF Pro; the model invented it.

---

## 6. Adaptive style rules (new feature you must design)

Today every mode uses the same prompt for every user. We want a layer
of *user-specific* style rules on top: the user pastes in a few of their
own past writings for a given mode, an LLM extracts the patterns, and
those patterns get baked into the mode's system prompt for all future
runs.

This section specifies the *whole* feature, not just the LLM bits. The
parts marked **[ENG]** are built by the Penny engineering team; you
treat them as given infrastructure. The parts marked **[PE]** are what
you, the prompt engineer, design.

### 6.1 Where it lives in the UI [ENG]

The existing Preferences window has a **Modes** section with a table of
modes plus Add / Edit / Delete buttons. The Edit sheet today has three
fields: **Name**, **Description**, **System prompt**.

We add a fourth and fifth section to that sheet:

```
┌─ Edit Mode "Slack" ─────────────────────────────────┐
│                                                     │
│ Name        [Slack                              ]   │
│ Description [succinct · warm · lowercase        ]   │
│                                                     │
│ System prompt (read-only for built-in modes)        │
│ ┌─────────────────────────────────────────────────┐ │
│ │ You are rewriting text as a Slack message ...   │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ Style examples (optional — up to 5)                 │
│ ┌─────────────────────────────────────────────────┐ │
│ │ 1. hey just shipped the auth fix 👀             │ │
│ │ 2. quick heads up that the deploy is ...        │ │
│ │ 3. (empty — Add example…)                       │ │
│ └─────────────────────────────────────────────────┘ │
│                       [ Re-extract style rules ]    │
│                                                     │
│ Learned style rules (refreshed 14:22, 19 May)       │
│ ┌─────────────────────────────────────────────────┐ │
│ │ • Sentences start lowercase, no end period      │ │
│ │ • Never sign off                                │ │
│ │ • Average length 1–2 short lines                │ │
│ │ • 👀 used to flag review-please items           │ │
│ │ • Hedges like "just" and "quick" common         │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│             [ Cancel ]   [ Save ]                   │
└─────────────────────────────────────────────────────┘
```

Behaviour:

- Examples are plain-text fields, one per row, add up to 5.
- The **Re-extract style rules** button is enabled when at least one
  example exists and the rules are stale relative to the examples.
- The **Learned style rules** list is editable in place — the user can
  add, delete, or reword any line. Edits persist; subsequent
  re-extractions don't blow them away (see §6.6).
- Deleting an example marks the rules as stale (timestamp turns red).
- When the user clicks Re-extract, a small inline progress indicator
  appears next to the button while the extraction call is in flight.

### 6.2 On-disk format [ENG]

User-supplied examples live alongside modes in `~/.penny/modes.json`
as a new optional field on each mode object:

```json
{
  "id": 4,
  "name": "Slack",
  "detail": "succinct · warm · lowercase",
  "isCustom": false,
  "isCancel": false,
  "locked": false,
  "prompt": "...",
  "examples": [
    "hey just shipped the auth fix 👀",
    "quick heads up that the deploy is broken — looking into it 🙏"
  ]
}
```

Extracted rules live in a separate file so they can be invalidated
independently, `~/.penny/style-rules.json`:

```json
{
  "4": {
    "rules": [
      "Sentences start lowercase, no end period",
      "Never sign off",
      "👀 used to flag review-please items"
    ],
    "extracted_at": "2026-05-19T14:22:11Z",
    "examples_hash": "sha256:7c0fa…"
  },
  "5": { … }
}
```

`examples_hash` is the sha256 of the joined examples; the engineering
side uses it to detect "examples changed since last extraction" and
flip the stale indicator. The prompt engineer doesn't have to think
about this field; it's purely engineering bookkeeping.

### 6.3 When extraction runs [ENG]

Three triggers:

1. **Explicit**: user clicks **Re-extract style rules**.
2. **Implicit after first example**: when the user adds an example
   and there are no rules yet for that mode, Penny prompts (with a
   small inline checkbox) to extract automatically.
3. **Never automatic on every save.** Extraction costs an LLM call;
   we don't fire it on every keystroke.

Extraction is run via the same Python helper that does refinement
(reuses the configured provider/model). The Swift app calls a new
subcommand on `refiner_cli.py`, passes the mode's intent + the
examples, gets back a JSON list of rules, writes them to disk,
re-renders the Preferences sheet.

### 6.4 The extraction prompt [PE]

This is one of the artefacts you deliver. It is **a different prompt
from the mode prompts**. The user-message payload is shaped like:

```json
{
  "mode_name": "Slack",
  "mode_intent": "succinct · warm · lowercase",
  "mode_base_prompt": "You are rewriting text as a Slack message ...",
  "examples": [
    "hey just shipped the auth fix 👀",
    "quick heads up that the deploy is broken — looking into it 🙏",
    "..."
  ]
}
```

Your prompt must produce a JSON response in this exact shape (so the
Swift side can parse it without a tolerant LLM-JSON parser):

```json
{
  "rules": [
    "Sentences start lowercase, no end period",
    "Never sign off",
    "👀 used to flag review-please items"
  ]
}
```

Constraints on what counts as a good rule:

- **Concrete and observable.** "Sentences start lowercase" is a rule.
  "Be more casual" is not.
- **Patterned, not idiosyncratic.** A rule must hold across at least
  two examples. One-off quirks don't make the cut.
- **Stylistic, not content.** "Often mentions the auth team" is content,
  not style — exclude.
- **Short.** Each rule is one line, ≤ 15 words. Easy to skim.
- **At most 10 rules.** Hard cap. If the extraction wants to surface 14
  patterns, it picks the 10 strongest.

Anti-rules (must not appear):

- Anything that just paraphrases the mode's existing base prompt.
- Statistics ("average length 23 words").
- Aspirations or vibes ("warm and friendly tone").
- Rules that would make the LLM hallucinate ("Always mention the
  user's role at the company").

### 6.5 How rules are injected at refinement time [PE]

You design the injection format. The Swift daemon hands the Python
helper the mode's base prompt plus the rule list; the helper sends
one combined system message to the LLM at refinement time.

You decide:

- **Whether the rules are a separate section or interwoven.** E.g.
  ```
  <base prompt unchanged>
  
  STYLE RULES (learned from your past writing):
  - Sentences start lowercase, no end period
  - Never sign off
  - 👀 used to flag review-please items
  ```
  vs. weaving them into the existing rule list.
- **What precedence rules have when they conflict with the base
  prompt** (they usually don't — base prompt is generic, learned rules
  are user-specific — but a Slack example user with rule "always end
  in a period" would conflict with the base prompt's "no end period").
- **Whether the rules appear before or after the OUTPUT RULE guard.**
  Probably after, so the user's rules can't accidentally override "no
  refusals" etc.

Whatever you choose, document it in `docs/prompt-design-notes.md` so
the engineering team can implement it.

### 6.6 User edits to rules [ENG, but you should be aware]

The rules list is editable in the UI. The user can:

- **Delete a rule.** It stays deleted across re-extractions. We track
  deleted rules per-mode in `style-rules.json`:
  ```json
  "4": {
    "rules": [...],
    "deleted_rules": ["Always uses three-dot ellipses..."],
    ...
  }
  ```
  On re-extraction, if the LLM proposes a deleted rule again, the
  helper filters it out before saving.
- **Edit a rule's wording.** Marks it as user-edited; future
  re-extractions don't overwrite user-edited rules.
- **Add a manual rule.** Same status as user-edited.

This means rules have three provenance flags: `extracted`, `edited`,
`manual`. All three appear identically in the UI; the difference only
matters for re-extraction merge logic.

### 6.7 Constraints summary

- **Opt-in.** Modes work fine with zero examples.
- **Auditable.** Every rule is plain English, surfaced in Preferences.
- **Bounded.** Max 10 rules per mode, max 5 examples per mode.
- **Reversible.** Deleting examples, deleting rules, and resetting the
  whole mode to defaults are all one click.
- **Audit log.** A user can see, at a glance, when the rules were last
  refreshed and what examples produced them. (The timestamp + collapsed
  examples list in the UI mock above is the audit log.)
- **No silent edits to the model.** Rules only change behaviour after
  the user clicks Re-extract or adds rules manually. Penny never
  modifies someone's prompt without an explicit action.

---

## 7. What you deliver

A pull request or patch containing exactly these artefacts:

1. **`config/modes.default.json`** — redesigned `prompt` field for each
   of modes 1–8. Same JSON shape as the current file. Other fields
   untouched.

2. **`config/style-extraction.prompt.txt`** — the system prompt for
   the rule-extraction LLM call described in §6.4. Plain text. The
   user message is built by the engineering side from the JSON
   payload in §6.4 and you can assume that shape.

3. **`config/style-rule-injection.template.txt`** — the template used
   at refinement time when a mode has learned rules. Uses simple
   placeholder substitution; document which placeholders you need
   in the comments at the top of the file. The engineering side will
   wire the substitution in `refiner/llm.py`. Example:

   ```
   {{base_prompt}}

   STYLE RULES (learned from this user's writing):
   {{rules_bulleted}}
   ```

4. **`docs/prompt-design-notes.md`** — one or two paragraphs per mode
   explaining what you changed and why. Plus a short section on the
   extraction prompt: which inputs you found mattered, which you
   ignored, and how the injection format was chosen.

5. **`docs/prompt-tests.json`** — at least 40 test cases total:
   - 30+ across modes 1–8 covering the §5 failure modes and edge
     cases you anticipate.
   - 10+ for the extraction prompt: given a set of inputs (`mode_name`,
     `mode_intent`, `mode_base_prompt`, `examples`), what rules
     should it produce?

   Schema:
   ```json
   [
     {
       "kind": "refinement",
       "mode": 1,
       "input": "thisss is a test",
       "expected": { "behaviour": "edited", "exact_output": "this is a test" }
     },
     {
       "kind": "refinement",
       "mode": 3,
       "input": "What is the biggest building in the world?",
       "expected": { "behaviour": "unchanged" }
     },
     {
       "kind": "extraction",
       "input": {
         "mode_name": "Slack",
         "mode_intent": "succinct · warm · lowercase",
         "mode_base_prompt": "<see modes.default.json>",
         "examples": ["hey just shipped...", "quick heads up..."]
       },
       "expected": {
         "min_rules": 3,
         "max_rules": 8,
         "must_contain_themes": ["lowercase", "no period", "informal"]
       }
     }
   ]
   ```

You do not write Swift or Python beyond these JSON / text files. The
engineering team wires up the style-rules UI, persistence, hashing,
provenance flags, and the substitution in `refiner/llm.py`. Your
contract is everything that goes into an LLM call: the mode prompts,
the extraction prompt, and the injection template.

---

## 8. Out of scope

- Anything about the dictation side of Penny.
- Anything about how the picker is rendered.
- Anything about Keychain, LaunchAgents, or the macOS layer.
- Anything about which provider / model to use; assume the user has
  configured a capable instruction-following model (Sonnet 4.6,
  GPT-4o, Gemini 2.5 Pro, etc.).

---

## 9. Acceptance criteria

A redesign is ready to ship when:

1. **No regressions on §5.** None of the failure modes documented in
   §5 reproduce on the listed inputs.
2. **Regression test set passes.** Every entry in `docs/prompt-tests.json`
   produces output matching its `expected` block when fed through the
   right prompt with a capable model.
3. **"No change required" path fires when it should.** At least one
   input per editing mode (1, 2, 3) returns byte-equal output, so the
   `✓ No change needed` toast appears instead of a pointless paste.
4. **Extraction prompt works on real data.** Given 3 user-supplied
   Slack examples (provided in the test set), the extraction prompt
   returns 3–8 concrete rules in valid JSON that a human reading the
   examples would also notice. None of the rules are anti-rules from §6.4.
5. **Injection format works.** When the rule-injection template is
   applied to a mode prompt + extracted rules, the resulting combined
   prompt produces refinements that visibly reflect the rules (a Slack
   mode user with the lowercase rule never gets sentence-case output).
6. **Token budget.** Every mode's base prompt is ≤ 600 tokens. The
   extraction prompt is ≤ 800 tokens. The injection template adds
   ≤ 200 tokens of overhead beyond the rules themselves.
7. **No mode ever pastes a refusal, a question, a label, or markdown
   fencing into the user's text field.** Verified by running every
   refinement test through the new prompts.

---

## Appendix A: full current prompts

See [`config/modes.default.json`](../config/modes.default.json) in this
repo. The fields you care about are `prompt` on each object. Modes 9
(Custom) and 0 (Cancel) have empty prompts and you do not edit them.

## Appendix B: the rest of the architecture (for context only)

- The Python helper that wraps the LLM call: [`refiner/llm.py`](../refiner/llm.py)
- The Python CLI that the Swift daemon spawns: [`refiner_cli.py`](../refiner_cli.py)
- Where the mode JSON gets loaded: [`refiner/prompts.py`](../refiner/prompts.py)
- The Swift side, for completeness: [`native/main.swift`](../native/main.swift) and friends.
