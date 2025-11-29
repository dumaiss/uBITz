# AI Stack Rationale – μBITz Platform

This document explains **why** we use different AI tools for different tasks in the μBITz project.

It is a companion to `AI-ASSISTED-DEVELOPMENT.md` (the **policy**) and provides the **technical rationale**  
behind our tool choices.

---

## Table of Contents

1. Design Principles    
2. The Tool Stack    
3. Task-to-Tool Mapping  
    3.5 Core vs. Non-Core Risk Lens    
4. Workflow Patterns    
5. Constraints and Trade-offs    
6. Tool-Specific Deep Dives    
7. Anti-Patterns (What We Don't Do)    
8. Evolution and Reevaluation
    

---

## Quick Reference: AI-Assisted Development in μBITz

### The Rules
- ✅ **Allowed:** AI for brainstorming, review, pseudocode
- ⚠️ **Core HDL:** AI assists design; human writes final code
- ✅ **Non-core:** More AI freedom; same understanding requirement
- ❌ **Prohibited:** Submitting AI code you can't explain

### Your Obligations
- Understand and own everything you submit
- Disclose non-trivial AI assistance in commits/PRs
- CLA/DCO still apply (AI doesn't change that)

### When in Doubt
- Can you explain this code line-by-line? → Proceed
- Is this core HDL? → Rewrite it yourself
- Did AI play a major role? → Note it in the PR

---

## 1. Design Principles

The μBITz AI stack is designed around these core principles:

### 1.1 Match Tool Strengths to Task Requirements

Different LLMs have different strengths:

- Context window size    
- Reasoning depth    
- Code generation quality    
- Iteration speed vs. message caps    
- Cost / friction profile
    

We deliberately assign tasks to tools based on these characteristics.

### 1.2 Separate "Thinking" from "Doing"

We often use:

- One tool for **architecture/evaluation**  
    (deep reasoning, cross-document analysis, “spec lawyer”)
    
- A different tool for **implementation/iteration**  
    (rapid code generation, autocomplete, small deltas)
    

This mirrors the **evaluator/implementor** split in our policy.

### 1.3 Repo-Based Memory, Not Vendor Lock-In

Long-term project memory lives in:

- Markdown dev logs (`Engineering Diaries/*_EngineeringDiary.md`)    
- Daily/weekly diaries (`Engineering Diaries/*_WeeklyDiary.md`)    
- Architecture documents (`*.md` in the spec/arch trees)    

Vendor tools are drafting environments. The **source of truth** is the Git repo.

### 1.4 Explicit Cost and Constraint Management

We acknowledge that:

- Some tools have hard message limits (e.g., Claude Pro)    
- Some tasks need 150+ micro-iterations (HDL refinement)    
- Some tasks need 1–3 deep sessions (spec audits, architecture reviews)    

The stack is designed to work **within** these constraints, not fight them.

### 1.5 Human-in-the-Loop by Design

All tools in this stack are used under the assumption that:

- AI proposes, critiques, and accelerates work.    
- A human **evaluates**, **decides**, and **implements**.    
- For any non-trivial change, a human can explain what was done and why, without  
    appealing to “because the model said so”.
    

This mirrors the evaluator/implementor pattern in `AI-ASSISTED-DEVELOPMENT.md`.

---

## 2. The Tool Stack

This is the _primary_ μBITz AI stack:

|Tool|Primary Role|Key Strength|Primary Weakness|Usage Pattern|
|---|---|---|---|---|
|**ChatGPT (web/Projects)**|Daily dev engine|Many iterations, Projects context, Canvas|Less deep cross-doc than Claude|Continuous, high-volume|
|**GitHub Copilot / Codex**|Code autocomplete|In-editor, instant feedback|No reasoning, file-limited|Continuous, in VS Code|
|**Claude Pro (UI)**|Spec reviewer & auditor|Deep reasoning, large context|Hard message caps|Periodic, high-impact|
|**Grok**|Branding & playful text|Fun, creative naming and copy|Not for serious technical work|Naming, taglines|

Other tools may be used experimentally or for non-μBITz side projects, but they are **not** part of the  
core μBITz stack unless and until they appear here.

---

## 3. Task-to-Tool Mapping

### 3.1 HDL Development (Core Work)

|Task|Tool(s)|Why|
|---|---|---|
|**Architecture brainstorming**|ChatGPT Projects + Canvas|Projects hold persistent context; Canvas acts as a live design doc|
|**Iterative HDL refinement**|ChatGPT → Copilot/Codex|Need 150–200 micro-iterations; ChatGPT can sustain this, Copilot speeds edits|
|**In-editor autocomplete**|GitHub Copilot/Codex|Instant feedback loop in VS Code for small deltas|
|**Deep spec audit**|Claude Pro (occasional)|Cross-reference multiple docs; spot inconsistencies and missing corner cases|
|**Test bench generation**|ChatGPT + Copilot|Volume task; Copilot assists with boilerplate, ChatGPT suggests scenarios/edges|

### 3.2 Documentation & Memory

|Task|Tool(s)|Why|
|---|---|---|
|**Daily and Weekly diaries**|ChatGPT Canvas → Markdown|Canvas captures decisions and rationale live|
|**Session summaries / Handoff / Definition of Done**|Claude → Markdown → repo|Deep reviews produce structured handoffs and summaries|
|**Architecture docs**|ChatGPT Canvas → Markdown → CAD|Canvas drafts; human refines; exports to spec/KiCad|

### 3.3 Creative & Non-Critical

|Task|Tool(s)|Why|
|---|---|---|
|**Feature naming / Branding copy**|Grok|Fun, slightly unhinged creativity; fits the retro-future μBITz aesthetic|

---

## 3.5 Core vs. Non-Core Risk Lens

The AI stack is applied with different levels of caution depending on the code:

- **Core HDL** (Dock decoder, IRQ router, Host–Bank contracts):
    
    - Follow the stricter rules in `AI-ASSISTED-DEVELOPMENT.md`.        
    - AI may help with architecture and review; final HDL is human-implemented.        
    - Extra scrutiny on explainability and IP cleanliness.
        
- **Non-core code** (Tiles, demos, examples, tools):
    
    - More freedom to use AI for scaffolding and boilerplate.        
    - Same requirement that the human contributor understands and owns the result.
        
This doc explains _why_ specific tools are chosen.  
The policy doc defines _how_ they may be used within these risk bands.

---

## 4. Workflow Patterns

### 4.1 Core HDL Development Loop

This is the **primary workflow** for implementing μBITz Dock modules like `addr_decoder.v`:

```text
1. [ChatGPT Projects] Brainstorm architecture for a component
   ├─ Define behavior and external contracts in natural language
   └─ Evolve the design in a Canvas (live design doc)

2. [ChatGPT → Copilot] Generate implementation instructions
   ├─ ChatGPT outputs "Codex-style" instructions:
   │    - add these signals
   │    - this FSM structure
   │    - these edge cases to handle
   └─ Treat this as a design brief, not final code

3. [VS Code + Copilot] Implement with autocomplete
   ├─ Copilot suggests lines/blocks based on existing code
   └─ Human reviews and accepts/rejects each suggestion

4. [Iterate] Repeat steps 2–3 for 150–200 micro-changes
   ├─ Fix bugs, refine edge cases, add features
   └─ ChatGPT handles the reasoning volume; Copilot handles local edits

5. [Promote to repo] When stable:
   ├─ Copy relevant Canvas content → `docs/...md`
   ├─ Copy final HDL → `rtl/dock/...v`
   └─ Write dev log entry → `docs/dev/..._DEVLOG.md`
```

**Why this works:**

- ChatGPT handles **volume** (many iterations).    
- Copilot handles **speed** (in-editor micro-changes).    
- Human handles **decisions and ownership**.    
- Git repo handles **memory and provenance**.    

---

### 4.2 Spec Audit & Deep Review (Claude-Centric)

This is the **occasional workflow** for catching spec/implementation drift:

```text
1. [Claude Pro] Provide all relevant specs and context
   ├─ Core Logical Specification (Part 1)
   ├─ Dock Specification (Part 2)
   └─ Profiles / relevant design docs

2. [Claude Pro] Ask cross-document questions
   ├─ "Does addr_decoder.v match Core spec §4.3 (window arbitration)?"
   ├─ "Find contradictions between Part 1 and Part 2"
   └─ "List all TBD/unresolved items across all docs"

3. [Claude Pro] Generate a handoff for ChatGPT
   ├─ Context: what was reviewed
   ├─ Findings: issues, inconsistencies, missing cases
   └─ Tasks: concrete actions, with a definition of done

4. [ChatGPT] Evaluate Claude's findings
   ├─ Triage (MUST_FIX vs NICE_TO_HAVE)
   ├─ Propose options for each item
   └─ Human decides which options to implement

5. [ChatGPT + Copilot] Implement selected items
   ├─ Generate concrete spec edits or HDL change plans
   └─ Apply in VS Code, using Copilot where helpful

6. [Repo] Save the review summary
   └─ `docs/sessions/YYYY-MM-DD-claude-core-spec-audit.md`
```

**Why this works:**

- Claude’s large context window handles **multi-document reasoning**.    
- ChatGPT handles **follow-up design and iteration** without hitting caps.    
- Human owns **prioritization and implementation**.    
- Session summary preserves the **audit trail**.    

---

### 4.3 Projects + Canvas as “Thinking IDE”

This pattern applies to both HDL and meta-work (like this AI policy/rationale):

```text
[Project Instructions]
  ├─ Define assistant behavior (e.g., "You are my HDL design partner")
  └─ Persist across sessions

[Canvas]
  ├─ Holds the evolving document (architecture, diary, rationale)
  ├─ Chat is used for discussion and decisions
  └─ Canvas updates in real-time with the current best version

[Outcome]
  ├─ Canvas content is "promoted" to the repo when stable
  └─ Chat history serves as an informal audit of how we got there
```

Example Projects:

- "μBITz Dock – Digital Architecture"    
- "μBITz – AI-Assisted Dev Workflow"    
- "μBITz – Daily Diary (Week of 2025-11-26)"
    

---

## 5. Constraints and Trade-offs

Before diving into specific tools, it helps to state the three main risks this stack is trying to manage:

- **Correctness risk** – HDL and specs must actually work; AI hallucinations must be caught.    
- **IP provenance risk** – We want to avoid verbatim or near-verbatim reproduction of unknown code.    
- **Constraint / friction risk** – Message caps, context limits, and workflow friction can quietly kill momentum.
    

The choices below are made with all three in mind, not just “which model is smartest”.

### 5.1 Why Not Use Claude for Everything?

**Constraint:** Claude Pro has hard message caps.

**Impact:**

- Not suitable for 150–200 iteration HDL workflows.    
- Best used for a small number of **high-impact** sessions (audits, reconciliations, spec reviews).
    

**Trade-off Decision:**

- Use Claude for **periodic deep reviews**.    
- Use ChatGPT for **daily high-volume iteration**.
    

**Result:** Depth when needed, volume when needed.

### 5.2 Why Not Base Everything on APIs (for now)?

**Constraint:** Pure API-based workflows lose Projects/Canvas and add dev/ops overhead.

**Impact:**

- No built-in persistent Project instructions across sessions.    
- No live design doc equivalent to Canvas.    
- Harder to maintain long-running architecture discussions.    

**Trade-off Decision:**

- Use ChatGPT **web UI** with Projects for main dev work today.    
- Treat APIs (Claude API, ChatGPT API, etc.) as _future, optional_ additions for narrow automation tasks.
    

**Result:** The Projects + Canvas pattern is too valuable to give up right now.

### 5.3 Why Not Let AI Generate All the HDL?

**Constraint:** Technical quality, IP provenance, and maintainability.

**Impact:**

- Risk of hallucinated or subtly broken logic in critical paths.    
- Unknown provenance if large blocks are pasted verbatim.    
- Future-you (or contributors) stuck with code they can’t explain.    

**Trade-off Decision:**

- AI can propose structures, patterns, and pseudocode.    
- Final core HDL is human-designed and human-understood.    
- Non-core code can be more AI-heavy, but with the same explainability requirement.    

**Result:** AI accelerates but doesn’t own the logic.

---

## 6. Tool-Specific Deep Dives

### 6.1 ChatGPT + Projects + Canvas: The Daily Engine

**Strengths:**

- Many iterations: no hard cap in normal use.    
- Projects context: persistent instructions tailored to μBITz.    
- Canvas: live document for specs, diaries, and design notes.    
- Good at “Codex-style” implementation instructions.
    

**Weaknesses:**

- Cross-document reasoning for big audits is weaker than Claude.    
- Requires manual copy/paste into VS Code for actual editing.
    

**Best for:**

- Daily HDL refinement and small design pivots.    
- Architecture brainstorming, evolving design docs.    
- Dev log and diary generation.
    

**Example workflow:**

```text
Me: "The addr_decoder needs to support Mode-2 vector fetch override.
     Recap the Core spec behavior and propose an implementation plan."

ChatGPT:
  1. Summarizes the relevant spec sections.
  2. Proposes signals and FSM changes.
  3. Outputs a structured change plan.

[Then I implement in VS Code, with Copilot assisting on syntax/boilerplate.]
```

---

### 6.2 Claude Pro (UI): The Deep Reviewer

**Strengths:**

- Large context window: can ingest multiple spec docs + excerpts of HDL.    
- Strong at cross-referencing and spotting inconsistencies.    
- Good at producing structured “handoffs” for other tools.
    

**Weaknesses:**

- Message caps make it poor for long iteration loops.    
- No Projects/Canvas equivalent; context is session-based.
    

**Best for:**

- Periodic spec audits.    
- “Does the implementation actually match the spec?” questions.    
- Generating clear handoffs for ChatGPT to implement.
    

**Example workflow:**

```text
Me: [Provide Core spec, Dock spec, and a description of addr_decoder.v behavior]

Me: "Check whether the current design actually satisfies the mask specificity rule
     and the intended error handling in §4.3. List mismatches and TBDs."

Claude:
  - Summarizes relevant spec rules.
  - Points out mismatches and edge cases.
  - Suggests clarifications to the text spec.

Me: "Summarize this as an action list for ChatGPT, with a definition of done."

Claude:
  - Outputs a structured handoff.

[Save the handoff into the repo and feed it to ChatGPT.]
```

---

### 6.3 GitHub Copilot / Codex: The Autocomplete Engine

**Strengths:**

- In-editor suggestions in VS Code.    
- Local context awareness (file + nearby code).    
- Great at repetitive patterns and boilerplate.
    

**Weaknesses:**

- No global reasoning; it just predicts what “looks right” syntactically.    
- Limited visibility outside the current file / small context window.
    

**Best for:**

- Implementing ChatGPT’s high-level instructions.    
- Adding signals, wiring ports, simple FSM cases.    
- Testbench scaffolding and small utility code.
    

**Example workflow:**

```text
ChatGPT plan: "Add a 3-bit priority encoder for IRQ channels."

In VS Code:
  - I write a comment: "// Priority encoder for IRQ channels"
  - Start typing the first line of logic.
  - Copilot suggests the rest of the always block.

I review the suggestion:
  - Accept if it matches the intended behavior.
  - Edit or reject if it's not correct or not clear.
```

---

### 6.4 Grok: The Hype Machine

**Strengths:**

- Creative, slightly chaotic naming and copy.    
- Good for taglines, feature names, and playful text.
    

**Weaknesses:**

- Not suitable for correctness-critical technical reasoning.    
- Output is optimized for “vibe”, not spec compliance.
    

**Best for:**

- Naming features and profiles.    
- Retro-flavored marketing copy.    
- Occasional morale boosts when slogging through HDL.
    

**Example workflow:**

```text
Me: "Suggest 10 fun names for the parallel bus profile
     that would fit a late-80s computer magazine ad."

Grok: ["Lightning Rail", "ThunderBus", "WarpLane", ...]

I pick/modify one and move on.
```

---

## 7. Anti-Patterns (What We Don't Do)

These are things we've **explicitly rejected** after trial or consideration:

### 7.1 ❌ Using Deep-Reasoning Models for Micro-Iteration

**Why it doesn’t work:**

- Claude-style models are best used sparingly for **big, high-impact questions**.    
- Burning message caps on “change this one signal name” is a waste.
    

**Alternative:**

- Use ChatGPT for iterative workflows.    
- Use Copilot for mechanical edits.    
- Save Claude for cross-doc audits and architecture questions.
    

---

### 7.2 ❌ Treating AI Output as Final Code

**Why it doesn’t work:**

- Violates the human-in-the-loop principle and the project policy.    
- Increases IP risk (potential verbatim reproduction).    
- Produces code you might not fully understand or be able to maintain.
    

**Alternative:**

- Treat AI output as **pseudocode, a hint, or a draft**.    
- For core HDL, always implement your own version, even if inspired by AI.
    

---

### 7.3 ❌ Hiding AI Usage

**Why it doesn’t work:**

- Undermines the meta-project goal (studying AI-assisted workflows).    
- Breaks trust with future contributors and users.    
- Makes it harder to reason about provenance if issues arise.
    

**Alternative:**

- Light disclosure in PRs/commit messages when AI played a non-trivial role.    
- Keep diary notes of interesting AI interactions and decisions.
    

---

### 7.4 ❌ Relying on Vendor "Memory" as the System of Record

**Why it doesn’t work:**

- Projects/“memory” features are opaque and vendor-specific.    
- You can’t diff or version-control them.    
- Hard to migrate if you change tools.
    

**Alternative:**

- Use Projects/Canvas only as **working environments**.    
- Promote stable outputs into the repo as Markdown/spec/HDL.    
- Treat the Git repo as the only real memory.    

---

## 8. Evolution and Reevaluation

This stack is **not static**. Tooling and models evolve; so will this document.

### 8.1 When to Reconsider Tools

We will revisit the stack when:

- New model releases change cost/quality trade-offs.    
- API offerings become compelling for automation.    
- Workflow friction appears (e.g., too many copy/paste steps).    
- A tool starts clearly underperforming in its current role.    

### 8.2 Meta-Project Feedback Loop

Because this is a **case study in AI-assisted development**, we:

- Track what works and what doesn’t in daily/weekly diaries.    
- Document rejected ideas and why in “Rejected / Deprioritized Ideas” sections.    
- Update this rationale document when we change patterns in practice.    
- Use concrete episodes (e.g., Dock decoder refactors) as case studies.    

### 8.3 Open Questions (As of 2025-11-29)

- Under what conditions would it be worth adding APIs (ChatGPT/Claude) for automation?    
- Are there narrow tasks (e.g., schematic/image reasoning) where adding another model would help?    
- What’s the right cadence for promoting diary content into more formal specs (per milestone vs per week)?
    

---

## Summary Table

|Tool|Use Case|Frequency|Why This Tool|
|---|---|---|---|
|**ChatGPT Projects**|HDL iteration, architecture|Daily|Many iterations, Projects context, Canvas|
|**GitHub Copilot / Codex**|In-editor autocomplete|Continuous|Zero-latency, local context|
|**Claude Pro (UI)**|Spec audits, deep review|Weekly/milestone|Large context, good at cross-doc reasoning|
|**Grok**|Naming, branding, fun copy|Occasional|Creative, matches the μBITz “voice”|

---

## Relationship to Policy

This document explains **why** we use the tools we use in μBITz.

The policy (`AI-ASSISTED-DEVELOPMENT.md`) explains **how** they may be used  
(human-in-loop, disclosure, core vs non-core rules).

Together, they form the complete picture of AI-assisted development on μBITz:

- **Policy:** The rules    
- **Rationale:** The reasoning    
- **Workflow docs / diaries:** The concrete day-to-day patterns and experiments
    

---

## Relationship to Traditional FOSS Practices (CLA / DCO)

This AI policy sits **on top of**, not instead of, the usual open-source contributor requirements:

- **Contributor License Agreement (CLA)** – if/when μBITz adopts one  
- **Developer Certificate of Origin (DCO)** – e.g., `Signed-off-by:` lines in commits  
- Project license terms (e.g., MIT/BSD/GPL)  

Those mechanisms already require that contributors:

- Submit **original work** or properly attributed derivatives  
- Do not knowingly infringe third-party IP  
- Take responsibility for what they contribute  

### 1. Human Responsibility Does Not Change

Using AI tools **does not change** any of that:

- You cannot say “the AI wrote it, not me”  
- By submitting a PR, you are still certifying that:
  - You understand the code you are sending  
  - You have the right to submit it under the project license  
  - It does not knowingly copy third-party material

AI is treated like any other tool (compiler, IDE, search engine):  
**you** are the author of the contribution.

### 2. How AI Use Interacts With CLA / DCO

Because LLMs are trained on large, opaque corpora, they introduce extra uncertainty about origin.  
This policy addresses that by requiring:

- **Human understanding**  
  - You should be able to explain what the code does and why it’s written that way  
  - “Because ChatGPT said so” is not an acceptable justification

- **Human rewriting for core HDL**  
  - For core μBITz logic (Dock decoder, IRQ routing, Host–Bank contracts, etc.),  
    AI may help with design ideas and review, but the final HDL must be written or
    intentionally re-written by a human contributor

- **Disclosure for non-trivial AI assistance**  
  - If AI had a **material influence** on a change (beyond simple spelling or formatting),  
    note it briefly in the commit message or PR description, for example:  
    `Note: AI-assisted (ChatGPT) for initial pseudocode; final HDL hand-written.`

This does **not** relax CLA/DCO obligations — it makes it easier to show that you met them in good faith.

### 3. Practical Examples

- **OK (Core HDL):**  
  - You ask an LLM to sketch a state machine in pseudocode  
  - You re-implement the FSM yourself in Verilog, adapting naming, structure, and details  
  - You can explain each state and transition  
  - You mention AI involvement in the dev diary and optionally in the commit

- **OK (Non-core / demos):**  
  - You let an LLM generate most of a demo program or example firmware  
  - You review it, fix issues, and confirm it fits the μBITz contracts  
  - You note in the PR that it was AI-assisted

- **Not OK:**  
  - You paste a large block of AI-generated HDL into a core module  
  - You cannot clearly explain it  
  - You submit it as if it were entirely original work

In all cases, **CLA/DCO still applies**. This policy just makes the AI part explicit so that
contributors, maintainers, and downstream users know how the code came to be.


---
## Appendix A – Survey of Similar Projects (Context for This Policy)

This policy was not written in a vacuum. It was informed by a quick survey of how other
hardware and systems projects are (or are not) dealing with generative AI.

The high-level pattern:

- Most projects are **silent** on AI use and rely on traditional CLA/DCO wording
- A few academic contexts encourage **disclosure** of AI use
- A very small number of projects (e.g., Asahi Linux) have adopted **explicit bans**

### A.1 Hardware Reverse Engineering (Asahi Linux)

- Works with **undocumented, proprietary hardware** (Apple Silicon)  
- Main concern: LLMs might regurgitate leaked or confidential vendor IP  
- Policy: **Total prohibition** of LLMs for contributions (“Slop Generators”)  
- Rationale: Protect a carefully constructed “clean-room” reverse-engineering process

**What μBITz borrows:**

- Awareness that LLMs create an auditable-origin problem  
- The need for a clear, project-level statement on AI use  

**What μBITz does differently:**

- μBITz is based on an **original spec**, not reverse engineering a closed platform  
- Instead of a ban, μBITz adopts **structured, human-in-the-loop use** with disclosure

### A.2 Open ISA / RISC-V Ecosystem

Examples: lowRISC (Ibex/OpenTitan), SweRV, various RISC-V cores and toolchains.

Typical characteristics:

- Rely on **CLA/DCO** and standard IP language (“must not infringe third-party rights”)  
- Do **not** explicitly mention LLMs or generative AI in contributor docs  
- Some projects experiment with AI for verification or test generation, but policies remain implicit

**What μBITz borrows:**

- The assumption that contributors certify originality via CLA/DCO  
- Focus on clean IP for HDL and toolchain code

**What μBITz adds:**

- An explicit AI policy on top of those assumptions  
- Human-in-the-loop rules for core HDL, rather than leaving AI use entirely implicit

### A.3 Academic / Research Projects

Example pattern: RISC-V/SoC research at universities (e.g., Rocket Chip).

Common approach:

- AI use is **allowed**, but contributors or authors are often asked to **disclose** it  
- Emphasis on academic integrity and transparency rather than prohibition

**What μBITz borrows:**

- The idea that **disclosure** is better than pretending AI was never involved  
- AI as a legitimate tool, provided the human can still stand behind the work

**What μBITz clarifies:**

- How disclosure and human responsibility interact with open-source obligations  
- That core HDL still needs a human author who can explain and maintain it

### A.4 General FOSS / Kernel-Style Projects

Example pattern: Linux kernel and similar large projects.

- Use **DCO** and strong review culture  
- No dedicated AI sections, but strong norms around understanding your patch, provenance, and licensing

**What μBITz aligns with:**

- The ethos that you should not submit code you don’t fully understand  
- The idea that tools (including AI) don’t change your responsibility for the patch

### A.5 Synthesis for μBITz

Taking all of these into account, μBITz chooses a middle path:

- **Not** a total ban (like Asahi)  
- **Not** silent (like most RISC-V and kernel projects)  
- **Not** purely academic (“just disclose”)  

Instead, μBITz adopts:

1. **Human-in-the-loop by default** – AI can assist; humans remain responsible  
2. **Stronger rules for core HDL** – AI may influence design, but final logic is human-owned  
3. **Lightweight disclosure** – enough transparency to reason about provenance and process  
4. **Compatibility with CLA / DCO** – this policy extends, rather than replaces, standard FOSS norms

This appendix is descriptive, not normative: it explains *why* μBITz has an explicit AI-assisted
development policy at a time when most similar projects do not.

As the wider ecosystem evolves and more projects publish AI policies, this appendix may be
updated with new examples and comparisons.


---

## Document History

- **2025-11-29:** Initial version based on ~1 month of μBITz AI-assisted dev work.
  