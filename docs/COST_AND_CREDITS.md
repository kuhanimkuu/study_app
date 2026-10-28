# AI cost and app credits (plan Step 4, 2026-10-27)

What one AI feature costs Study OS on the hosted model, and the credit prices that come from it.
Prices are in `server/domains/billing/credits.py`. Re-check them with
`python -m server.scripts.cost_report` once real students use the hosted tier.

Model: **deepseek-chat**, $0.27 per million input tokens and $1.10 per million output tokens
(`billing/pricing.py`, last checked 2026-09-20; check DeepSeek's pricing page before launch).

## 1. Measured averages

These come from the real-model teacher eval on 2026-10-27 (`server/scripts/teacher_eval.py`, `eval_runs/`).
It ran 16 calls: 10 questions, 4 check conversations and 1 lesson.

| | input tokens | output tokens | cost |
|---|---|---|---|
| The whole run (16 calls) | 4,894 | 8,938 | $0.0112 |
| One call on average | ~306 | ~559 | **~$0.0007** |

What each feature costs on average:

- **Chat reply** (260–420 words, plus the marking call when the student answers a check): about **$0.0007**.
- **Lesson** (5 steps of about 150 words, a worked example and checks): about 500 input and 1,100 output tokens, so about **$0.0013**.
- **PDF summary / study guide:** not run in the eval. From its prompt and usual length it is about 300 input and 1,200 output tokens, so about **$0.0014**.

The eval logs its calls without a per-feature split, so the lesson and PDF figures are estimates from word counts.
The token meter now logs every call under its feature (`chat`, `chat_exam`, `pdf_summary`, `lesson`, `go_deeper`, …).
`cost_report.py` prints the real averages per feature.

## 2. Worst case per feature

Every feature has a hard cap on output (`server/ai/moderator/style.py` and each call's `max_tokens`).
That makes its biggest possible bill known. Inputs below are generous upper estimates
(6 turns of history, retrieved notes, the prompt).

| feature | worst input | worst output | worst cost | price | sells for |
|---|---|---|---|---|---|
| Chat answer (quick/full; reply 1,400 + marking 1,200) | 6,000 | 2,600 | $0.0045 | 1 credit | $0.01 |
| Exam-level answer (2,240 + marking 1,200) | 6,000 | 3,440 | $0.0054 | 2 credits | $0.02 |
| PDF document (chat or Studio, any template; up to 24k chars of sources) | 8,000 | 5,000 | $0.0077 | 2 credits | $0.02 |
| Lesson | 3,000 | 5,000 | $0.0063 | 3 credits | $0.03 |
| Go deeper (picking sources) | 5,000 | 700 | $0.0021 | 1 credit | $0.01 |
| Explanation | 3,000 | 1,500 | $0.0025 | 1 credit | $0.01 |
| Practice questions / flashcards | 6,000 | 2,350 | $0.0042 | 2 credits | $0.02 |
| Marking a written answer | 3,000 | 300 | $0.0011 | 1 credit | $0.01 |
| "Test my AI" | — | — | — | free | — |

The dearest feature per credit is a plain chat answer: at most $0.0045 per credit.
`test_every_feature_price_covers_its_worst_case_on_deepseek` fails if a price ever drops below its worst case.

## 3. Packs and plans

One credit sells for $0.01. Until real payments exist, top-ups are test ones (`payment_provider.py`, mock).

| pack | credits | price | price per credit | worst cost of all its credits |
|---|---|---|---|---|
| small | 100 | $1 | $0.0100 | $0.45 |
| medium | 550 | $5 | $0.0091 | $2.48 |
| large | 1,200 | $10 | $0.0083 | $5.40 |

There are proposed monthly plans for later; no subscriptions are built yet.

| plan | price | credits a month | worst-case cost | after a 30% app-store fee |
|---|---|---|---|---|
| Starter | $2 | 200 | $0.90 | $1.40 net, so it still covers the worst case |
| Student | $5 | 600 | $2.70 | $3.50 net, so it still covers the worst case |

A heavy student is assumed to get about 30 answers a day. That costs about **$0.63 a month** at the measured average,
well inside either plan.

## 4. The hidden allowance

Students see credits only. The app shows no provider cost, markup, per-token charge or provider choice,
and the server picks the hosted model (`HOSTED_DEFAULT_PROVIDER`, default `deepseek`).
Behind the credits, `service.enforce_hosted_allowance` limits what one student's hosted calls may cost Study OS
in a calendar month. It uses the smaller of two caps:

- **What their spent credits sold for, plus 10 cents.** This keeps the worst case below the price even if the hosted model
  is switched to a dearer one before the prices change.
- **`HOSTED_MONTHLY_COST_CAP_USD`** (default $3). This is a fair-use ceiling.
  While top-ups are free test ones, this is what stops one account from using the pooled key without limit.
  Raise it when real payments start.

A student who reaches either cap is told that this month's AI allowance is used up and renews on the 1st,
and that they can use their own key until then. No dollar amount is shown.

The student's own dollar spending limit (Profile → AI usage) now counts only calls made with their own key.

## 5. Still open

- Real payments: Stripe (web) or app-store billing. Store billing takes 15–30%, which the plan table already allows for.
- Re-run `cost_report.py` after a month of real use and re-price any feature whose largest call nears its price.
- If the hosted model changes (for example to Claude or GPT), redo section 2 first.
  Claude Sonnet is about 14× dearer per token, and the allowance would then block students well before their credits run out.
