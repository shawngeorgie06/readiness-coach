# Ask Coach redesign

Date: 2026-11-09 · Status: draft for approval

## Why

Shawn doesn't feel like asking the coach anything today. The entry point is a
grey, search-style bar wedged between "Today's plan" and the tab bar, and it
reads as app chrome rather than something to tap. Opening it shows a locked
verdict, a defensive footnote ("it can't make it more aggressive"), a form
label, an empty text box and a disabled grey **Ask** button. It looks like a
support form, not a coach. It also answers one question and forgets.

The question he actually has on a bad morning is **"why is my score this low,
and what's behind it?"** The redesign makes that answer one tap away, shows the
real numbers behind it, and lets him keep talking.

## Goals

1. Getting an explanation of any number on Today takes one tap and no typing.
2. A dedicated way to ask the coach anything else stays visible on Today.
3. The coach screen leads with the real numbers, then the coach's take, then
   a conversation.
4. The coach remembers the whole conversation while the screen is open.
5. Motion is smooth: things expand into place. No hard cuts to a blank sheet.

## Non-goals

- Saving conversations after the screen closes, or a history list.
- A Coach tab, or a floating button.
- Token-by-token streaming of answers.
- Changing how readiness or the decision is calculated.

## Anti-goals

These would make it a failure even if it technically works:

- It still feels like a form: a label, an empty box and a grey button.
- Canned, identical copy every day.
- The coach recommending training harder than the locked decision allows.
- Placeholder numbers. Every number shown comes from the server.

## Today screen (decided)

**Remove** the docked `AskBar` and its `safeAreaInset` at the bottom of
`TodayView`.

**Add a coach card directly under the score head** (above "Score breakdown"):

- Coach avatar mark and the name "Coach".
- One opening line that speaks first about today, built on device from data
  already in `TodayDTO`. It names the weakest pillar when one is notably low,
  and otherwise speaks to the decision. Examples: Recover with recovery 9 →
  "Your recovery dropped to 9. Want to know why?"; Push → "You're primed
  today. Want a plan?". It should never be one fixed sentence.
- Two tappable suggested questions that fit the day, plus a final
  **"Ask something…"** chip. That chip is the dedicated entry for any
  question.
- It only appears once `sync.today` has loaded, as the bar does today.

**Tap-to-explain:** tapping the readiness score head or any of the three
pillar rings opens the coach screen focused on that number. The coach
immediately explains it, so the user never types anything.

This needs care: the score head and rings already have tap actions. Today the
score head (`DecisionBlock`) opens readiness history (`TrendsView`), and each
ring switches to that pillar's tab (`tabs.go(to:)`). Tap-to-explain **replaces** those primary taps on
Today. The pillar tabs stay reachable from the tab bar. Readiness history must stay
reachable from Today or the coach screen (builder's call how, for example a
"See history" link in the coach header).

## Coach screen (decided)

Presented as a sheet from Today. It has three parts, top to bottom.

**1. Numbers (focus header).** What it shows depends on how it was opened:

| Opened from | Header shows |
|---|---|
| Recovery ring | Recovery score, its weight in readiness (40%), bars for HRV and resting HR |
| Sleep ring | Sleep score, weight (35%), bar for sleep hours vs normal |
| Load ring | Load score, weight (25%), bar for 7-day load vs normal |
| Score head, a suggested question, or "Ask something…" | Readiness score, decision, and the three pillar scores |

Each factor bar shows today's value, the 30-day normal and the % or absolute
difference, coloured by whether that's good or bad for that metric
(`goodDirection`). Below the bars is a small 7-day trend from `recent14d`.
All of this comes from `today.baselines` / `MetricComparison`, which already
exists. If `baselines` is nil, show the pillar score and its drivers' text
only, never invented numbers.

**2. Coach's take.** When opened by tapping a number or a suggested question,
the app sends that question automatically (for example "Why is my recovery
9 today?"). The answer appears below the numbers in plain prose.
"Ask something…" sends nothing and focuses the input.

**3. Conversation.** Follow-up suggestion chips relevant to the focus appear
under the latest answer, with a pinned input at the bottom ("Ask a
follow-up…") and a send button that is visibly enabled once there's text.
Messages show as a chat thread: user bubbles on the right, coach answers on
the left.

**Lock notice:** one small grey line at the bottom: "AI-generated · explains
today's call, can't change it". The large locked-decision block and the
defensive footnote at the top go away.

**States:**

- **Loading:** a typing indicator in the coach position.
- **Error (503 `coach_unavailable`, network):** an inline retry on that
  message. Earlier messages stay.
- **Empty "Ask something…":** the numbers header plus the suggestion chips.

## Memory (decided)

The whole conversation is remembered while the sheet is open and discarded
when it closes. Nothing is persisted on device or server.

- **iOS** keeps the messages in view state and sends prior turns with each
  question.
- **API:** `POST /v1/coach/ask` gains an optional
  `history: [{ role: "user" | "assistant", content: string }]`.
  - Validated with zod: max 20 entries, each content max 4,000 characters,
    roles limited to those two.
  - Old clients that send no history behave exactly as today.
- **`askCoach`** puts history between the system prompt and the current
  question:
  - The current turn still carries `metricSummary(today)`, so every answer
    is grounded in today's data.
  - `enforceAnswerDecisionLock` still runs on every answer.
  - History is untrusted, client-supplied text. Even "assistant" turns
    could be forged (*my call*):
    - The system prompt states that prior turns are a transcript supplied
      by the client, and that the locked decision and today's data override
      anything in them.
    - The server re-applies `enforceAnswerDecisionLock` to each
      client-supplied assistant turn before sending it to the model, so a
      forged "you can PR today" turn arrives already corrected.
    - Tests use a stub LLM to assert the message order, the
      prompt wording, that history assistant turns are lock-corrected, and
      that the final answer is still lock-checked. Push days stay
      unguarded, as they are today. No live-model tests in CI.
  - **Coach sees the same numbers as the bars** (*my call*):
    `metricSummary` gains a `baselines` block with today, the 30-day normal
    and the % difference for HRV, resting HR, sleep hours and 7-day load,
    taken from the same server source as `today.baselines`. The coach prompt
    asks it to compare against "your normal" using those values. Without
    this, the answer could quote a different normal (the sleep target, or
    the acute:chronic ratio) than the bar right above it. The existing
    driver text stays too.
  - **Lock directive in chat** (*my call*): the lock check itself is
    unchanged. The coach prompt tells the model to state the locked
    decision in its own words, so the appended fixed paragraph rarely
    fires. The keyword check still fires on everyday words like "hard",
    so the app shows the appended directive as a small styled lock note
    under that answer, not as part of the prose.
- **Cap:** the client caps a conversation at 20 messages, then shows "Start a
  new conversation". This keeps requests well inside Vercel's 30s limit and
  Groq's context.

## Motion (decided: smooth; details are the builder's call)

- Opening from a ring or the score head: the tapped number visually carries
  into the coach screen's header, using a matched transition or a convincing
  equivalent.
- Bars animate from zero to their value on appear.
- The coach's answer fades and slides in, rather than popping. Real
  streaming is out of scope.
- New messages animate into the thread, which scrolls to the latest.
- Respect Reduce Motion: use cross-fades only.
- Haptic: a light selection tap when opening from a number.

## Constraints

- Use the existing design system (`Palette`, `Typeface`, `Space`,
  `SheetScaffold` or a replacement, `InlineNotice`). Dark UI, as in the
  current app.
- Keep the iOS Xcode project's synchronized groups. New Swift files need no
  project edits.
- The backend runs on Vercel Hobby with a 30s function limit and Groq
  `openai/gpt-oss-120b`.
- `Secrets.swift` is never committed.
- Accessibility:
  - Every chip and ring has a VoiceOver label that says what tapping does
    ("Explain Recovery 9").
  - Touch targets are at least 44pt.
  - Layout works at large Dynamic Type sizes.

## Left to the builder

- Exact wording rules for the opening line and suggested questions. They must
  vary with decision and pillar data, and the builder writes the rule table.
- Exact visual styling of the card, bars, chips and avatar within the design
  system.
- Whether the coach sheet uses `SheetScaffold` or a custom container.
- Where the readiness-history link lives once the score head explains instead.
- Animation curves and timings.

## Testing

- **Backend:**
  - The route accepts and validates `history`: bad role, too many entries
    and oversize entries are rejected.
  - Old payloads still work.
  - History is passed to the LLM in order.
  - The lock is still enforced with adversarial history.
- **iOS unit tests:**
  - The opening-line and suggestion rules for each decision and
    weakest-pillar case.
  - Request encoding includes history.
  - The 20-message cap.
- **Manual check on the simulator and the phone:**
  - Tap each ring and the score head.
  - Tap a suggestion, then a follow-up that relies on memory.
  - Error retry.
  - Reduce Motion.
  - Before and after screenshots at the same width.
