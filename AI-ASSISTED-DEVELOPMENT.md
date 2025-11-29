# AI-Assisted Development Policy – μBITz Platform

μBITz is both:

1. A novel hardware and HDL platform, and  
2. A meta-project to explore **AI-assisted development workflows** in practice.

We **do** use Large Language Models (LLMs) such as ChatGPT, Claude, DeepSeek, Gemini, Grok, Copilot, etc.

However:

> **AI is always a tool, never the author.  
> A human is always in the loop, makes the final decisions, and owns the result.**

In practice we often separate roles into an **“evaluator”** (who reasons about designs, reviews AI suggestions)
and an **“implementor”** (who writes and refines the actual code). AI can support either role, but never replaces them.

This document explains how AI tools **may** and **may not** be used when contributing to this repo.

---

## 0. Core principle: human-in-the-loop, human in charge

All contributions to μBITz must respect these principles:

- **Human ownership**  
  Every change is owned by a human contributor who understands it and can explain it.
  AI can propose, critique, or refactor, but the human decides what is kept.

- **Human review of AI output**  
  No AI-generated text or code is accepted “on faith”. It must be reviewed, edited,
  and integrated by a human, just like any other third-party suggestion.

- **Separation of roles when useful**  
  For larger changes, we may explicitly separate:
  - an **evaluator** (reviews design, specs, and AI suggestions), and
  - an **implementor** (writes and iterates the final HDL or code).
  
  AI may participate in the evaluation step, but the implementor is responsible
  for the final implementation.

---

## 1. Scope and terminology

- **AI tools / LLMs**: ChatGPT, Claude, Gemini, DeepSeek, Grok, GitHub Copilot, etc.
- **Core HDL**: Verilog/VHDL that implements μBITz *contracts*:
  - Dock address decoder / windowing logic
  - Dock IRQ router / acknowledge logic
  - Host–Bank bus glue and protocol-critical modules
- **Non-core code**: Tile implementations, test benches, scripts, utilities, examples, etc.
- **Docs**: Specifications, Markdown docs, diagrams, comments.

---

## 2. Design goals

Our policy is trying to balance three things:

1. **Innovation and realism**  
   μBITz is explicitly a case study in AI-assisted development. We *want* to use LLMs
   and document what happens.

2. **IP and license safety**  
   We do **not** want to ship HDL that is a verbatim or near-verbatim copy of unknown code
   scraped from the internet, nor silently inherit incompatible licenses.

3. **Human understanding and control**  
   Any contributor who touches HDL must be able to explain what it does without deferring to an AI.
   Final technical decisions are always human decisions.

---

## 3. Allowed AI usage

You may use AI tools for:

- **Brainstorming and clarification**
  - Asking for explanations of HDL constructs, bus protocols, timing issues.
  - Asking for alternative architectures or refactoring ideas.

- **Design and review support (evaluator role)**
  - Having a model point out potential bugs, race conditions, or corner cases.
  - Asking for “devil’s advocate” critiques of a design.
  - Comparing a proposed implementation to the μBITz spec.

- **Test and tooling help**
  - Generating *candidate* testbenches, assertions, or small utility scripts.
  - Proposing edge cases or fuzzing strategies.

- **Documentation**
  - Drafting or polishing English/Japanese documentation and comments.
  - Summarizing specs, generating diagrams, etc.

In all these cases, the human contributor:

- Reviews the AI output,  
- Decides what (if anything) to adopt, and  
- Is responsible for the correctness and fit with the μBITz specs.

---

## 4. Restricted and prohibited AI usage

### 4.1 Core HDL (contracts and critical logic)

For **core HDL modules**, the following rules apply:

- ❌ Do **not** paste large blocks of AI-generated HDL directly into these files.
- ❌ Do **not** accept AI-generated logic you cannot explain.
- ✅ You **may** use AI to:
  - discuss the design,
  - explore algorithms,
  - sketch pseudocode or alternate formulations.

The final HDL in core modules must be:

- Written or significantly rewritten by a human implementor, and  
- Something that implementor can explain line-by-line and justify against the spec.

Think of AI here as a *reviewer* or *sounding board*, not a co-author.

### 4.2 Non-core code

For tiles, examples, and non-critical modules:

- AI-generated code is allowed **with conditions**:
  - You understand what it does and can maintain it.
  - You are willing to modify and debug it yourself.
  - You do not knowingly paste code that is obviously copied from a specific project.

When in doubt:

- Treat AI output as **pseudocode**,  
- Then write your own version:
  - adjust identifiers,
  - change structure,
  - adapt comments and style.

### 4.3 Absolutely prohibited behavior

- Submitting code you do not understand, “because the AI said so”.
- Intentionally prompting an AI to imitate a specific proprietary core or project.
- Hiding AI usage when asked explicitly in a review.
- Using AI to bypass your own responsibility as evaluator/implementor.

---

## 5. Contributor expectations

When you open a PR that includes HDL changes:

1. **Disclosure (lightweight)**
   - If AI assisted in a non-trivial way, mention it in the PR description, e.g.  
     > "AI-assisted: initial draft/review with Claude, final HDL written and verified by me."

2. **Explainability**
   - Be prepared to explain:
     - What the module does,
     - How the state machine or combinational logic works,
     - How it satisfies the relevant μBITz spec.
   - If you used an evaluator/implementor split, be clear about which role you played.

3. **License hygiene**
   - Do not paste in code that you copied from another project (with or without AI).
   - If you are intentionally adapting code from a known open-source project,
     state the source and license so we can handle attribution correctly.

---

## 6. Maintainer responsibilities

Maintainers may:

- Ask you to clarify how AI was used on a given change.
- Request a refactor or rewrite of suspicious HDL, especially in core modules.
- Reject contributions that:
  - appear to be low-effort AI dumps, or
  - you cannot explain as the human implementor.

Before major tagged releases, maintainers may run automated license scanning tools and
rewrite or remove any flagged sections.

---

## 7. Meta-project and research angle

Because μBITz is also an AI-assisted development **case study**, we may:

- Keep diaries or logs describing how AI tools were used in practice.
- Publish anonymized examples of AI-assisted workflows (good and bad).
- Evolve this policy as models, tools, and legal norms change.

If you contribute, you implicitly accept that your PRs may be used as case material
for discussing AI-assisted workflows (purely on the technical/process side), with
the understanding that **humans are always the final evaluators and implementors**.

## 8. Examples

### ✅ Good: AI-Assisted Core HDL:

1. Discuss addr_decoder arbitration logic with Claude
2. Claude suggests priority encoder approach
3. You write the Verilog yourself, using priority encoder concept
4. You verify against spec and test
5. PR notes: "AI-assisted: discussed arbitration approach with Claude"

### ❌ Bad: AI-Generated Core HDL:
1. Paste spec into ChatGPT: "generate addr_decoder.v"
2. Copy output directly into repo
3. Submit PR without understanding the state machine

### Recommended tool usage by task:
- **Architecture review**: Claude Pro (cross-doc reasoning)
- **Iterative HDL refinement**: ChatGPT + Codex (high iteration count)
- **Spec compliance check**: Claude (context window)
- **Code review automation**: GitHub Copilot (inline suggestions)

## Pre-release checklist:
- [ ] Run `scancode-toolkit` on all `.v` and `.vhd` files
- [ ] Review any flagged similarities >10 consecutive lines
- [ ] For flagged sections: verify independent creation or add attribution
- [ ] Update LICENSES.md with any new attributions