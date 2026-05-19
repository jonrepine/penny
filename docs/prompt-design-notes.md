# Prompt design notes

## Mode 1 — Spelling only

The spelling prompt is narrowed to one responsibility: correct spelling and nothing else. I made stretched-letter typos explicitly in scope, including plural endings such as `chickensssssss -> chickens`, because that was a documented production failure. The prompt also protects names, URLs, code, and product terms unless the correction is certain, which keeps it from guessing at domain-specific vocabulary.

The no-change path is explicit: if no safe spelling fix exists, the input must be returned exactly unchanged. That preserves Penny's exact-match toast behavior and avoids destructive cosmetic edits.

## Mode 2 — Grammar

The grammar prompt separates mechanical correctness from writing improvement. It permits spelling, grammar, punctuation, capitalization, fragments, and run-ons, but blocks style rewriting, shortening, reordering, and formatting normalization. This keeps grammar mode predictable for users who only want correctness.

The prompt asks for the smallest safe correction when meaning is unclear. That gives the model permission to leave ambiguous text alone instead of manufacturing intent.

## Mode 3 — Improve Writing

Improve Writing now explicitly says never to refuse and to work with whatever text is given. This directly addresses the failure where a question was replaced by refusal text. The prompt allows tightening, flow, and mechanical fixes, while forbidding additions, answers, invented context, and changes to certainty or stance.

For short questions, labels, commands, and already-clear text, it tells the model to prefer unchanged over cosmetic edits. This keeps the mode useful without turning every selected phrase into model-voiced prose.

## Mode 4 — Slack

The Slack prompt keeps the target style hard-coded: succinct, warm, lowercase starts, no formal greeting/sign-off, no final period, and emoji-sparing. I tightened the no-invention language so the model cannot add urgency, names, dates, promises, or asks while trying to sound warm.

The mode still supports an unchanged path for text that already fits the Slack style. That matters because Slack drafts are often already close to final and Penny should not churn them unnecessarily.

## Mode 5 — Email

The email prompt keeps the required warm polish and final `Cheers,` sign-off, while removing encouragement to generate templated openers from thin context. It now says greetings should only be included when present or clearly needed, and otherwise missing recipient information should stay as `[Name]` rather than being invented.

The prompt is strict about not adding attachments, deadlines, commitments, names, or context. This is important because email rewrites are high-risk: a plausible invented detail can become an accidental promise.

## Mode 6 — Report

The report prompt preserves the Notion-style target but makes source-grounding the first principle. It asks for layered Markdown, functional emoji, callout-style detail blocks, and analytical prose, but tells the model to omit empty sections instead of fabricating a full report skeleton.

This reduces the risk of made-up findings or recommendations while still producing a polished Notion artifact when the source text contains enough substance.

## Mode 7 — Bullet Points

The bullet prompt now defines the transformation tightly: hyphen bullets, one idea per bullet, preserve order and uncertainty, no invented headings or categories. It also includes an unchanged path for already-clean bullet lists.

This prevents the model from adding summary labels or conclusions, which would be destructive in an in-place paste workflow.

## Mode 8 — Improve Prompt

The prompt-improvement mode is explicitly a rewrite-only mode: it must not answer or perform the user's task. It emphasizes scoped improvement, bracketed placeholders for missing context, and a ban on invented tools, frameworks, examples, constraints, or deliverables.

This targets the observed failure where a vague request became an over-specified design brief. The new prompt should turn vague input into a clearer prompt, not a fabricated specification.

## Learned style-rule injection

Learned rules should be appended after the base mode prompt using `config/style-rules.fragment.txt`. The fragment states the priority order: source meaning and paste safety first, base mode rules second, learned style third. This keeps personalization opt-in and auditable without letting extracted preferences override safety-critical instructions.

## Style extraction

The extraction prompt returns only a JSON array of short, concrete, user-visible rules. It caps output at ten rules, rejects generic advice and one-off noise, and avoids extracting facts or sensitive attributes from examples. This gives Preferences a plain-English rules log that users can review, edit, or delete.
