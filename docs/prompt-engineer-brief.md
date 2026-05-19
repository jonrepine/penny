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
of *user-specific* style rules on top.

### 6.1 The user-facing flow

In Preferences → Modes, each mode has an optional **"Style examples"**
section. The user can paste in 1–5 examples of previous work they want
to emulate for that mode:

- For Slack mode: a few of their actual Slack messages.
- For Email mode: a few of their actual sent emails.
- For Report mode: a Notion report they're proud of.
- For Improve Writing mode: a paragraph they think reads well.

When the user submits examples, Penny sends them to the LLM with a
**rule-extraction prompt** (which you also design). The LLM returns a
list of concrete style rules — patterns it detected — that get appended
to the mode's system prompt going forward.

The user sees the extracted rules in the same Preferences pane, can edit
them, and can delete examples or rules at any time.

### 6.2 What the rule-extraction prompt must produce

For each mode the user provides examples for, the extraction prompt
must return a JSON array of short, concrete rules. Examples of what
a good rule looks like (these are illustrative; you decide the format):

- "Sentences typically start lowercase except for proper nouns."
- "Messages rarely exceed three lines."
- "Sign-offs are never used."
- "Numbers under ten are written as words."
- "Emojis used sparingly — typically 🙏 for thanks, 👀 for review-please."

What a *bad* rule looks like (must be avoided):

- "Be more concise." (too vague; not a pattern, a vibe)
- "Match the user's tone." (already a global rule; not extracted from
  examples)
- "Sentences vary in length from 4 to 23 words." (statistical noise,
  not a meaningful pattern)

### 6.3 The "rules log"

Once extracted, rules are stored in `~/.penny/style-rules.json`,
keyed by mode id. The preferences window has a panel per mode showing:

- The user's submitted examples (collapsed by default).
- The extracted rules (editable text list).
- A timestamp of when rules were last refreshed.
- A "Re-extract from examples" button.

The rules are appended to the mode's base system prompt at refinement
time. You should design how this appending happens — for example, as
a `STYLE RULES (learned from this user's examples):` section after the
mode's base instructions, or interwoven with the mode's existing
rule-list, whichever produces better LLM behaviour.

### 6.4 Constraints on the style-rule system

- **Opt-in.** Modes work fine with zero examples. The user is not
  required to provide them.
- **Auditable.** Every rule shown to the user must be in plain English,
  not buried in a JSON blob they can't read.
- **Limited.** If the LLM extracts 40 rules, that's a smell. Suggest a
  reasonable cap (e.g. 10 per mode) and have the extraction prompt
  enforce it.
- **Reversible.** Deleting examples deletes the rules they generated.
  Deleting individual rules works too.

---

## 7. What you deliver

A pull request or patch containing:

1. **New `config/modes.default.json`** with your redesigned prompts for
   modes 1–8. Use the existing JSON structure.
2. **A new prompt for the style-rule extraction LLM call** (one file:
   `config/style-extraction.prompt.txt` or similar).
3. **A new prompt fragment for how learned rules get injected** at
   refinement time (could be a template string, e.g.
   `"\n\nSTYLE RULES (learned from your examples):\n{rules}\n"`).
4. **A short rationale doc** — one or two paragraphs per mode
   explaining what you changed and why. Lives at
   `docs/prompt-design-notes.md`.
5. **A regression test set**: at least 30 inputs across the 8 modes
   covering the failure modes in §5 plus your own. JSON file at
   `docs/prompt-tests.json` with `{mode, input, expected_behaviour}`
   where `expected_behaviour` is one of `unchanged`, `edited`,
   `restyled`, with notes for nuanced cases.

You do not write Swift or Python beyond JSON config files. The
engineering team wires up the style-rules UI and persistence; you
specify *what should be sent to the LLM*, not how.

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

1. None of the failure modes in §5 reproduce on the listed inputs.
2. The regression test set in §7.5 passes when each input is fed
   through the corresponding mode's new prompt.
3. The "no change required" detection (input == output, byte-for-byte)
   triggers on at least one input per editing mode (1, 2, 3) where the
   input is genuinely already correct.
4. The style-rule extraction prompt, given 3 user-supplied Slack
   examples, returns 5–10 concrete rules in valid JSON that a human
   reading the examples would also notice.
5. Every mode's prompt is under 600 tokens (current `config/modes.json`
   has some that are bloated — we'd like them tightened along the way).
6. No mode ever pastes a refusal, a question, a label, or markdown
   fencing into the user's text field.

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
