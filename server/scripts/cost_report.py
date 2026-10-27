"""
What each AI feature really costs (Study OS plan, step 4).

Reads the token meter (ai_usage) for every student, groups the calls by
feature, and prints the average and largest tokens per call, what they
cost — and what they would cost on deepseek-chat, the hosted model the
credit prices assume — next to each feature's credit price. Run it on the
server once students have used the app for a while, and re-price
billing/credits.py if a feature's largest call comes near its price.

    python -m server.scripts.cost_report            # last 30 days
    python -m server.scripts.cost_report --days 7

Read-only, and no student is named: only totals per feature.
"""
from __future__ import annotations

import argparse
import asyncio
import datetime

from sqlalchemy import func, select

from server.db.session import async_session
from server.domains.billing import credits, pricing
from server.domains.billing.models import AiUsage

MODEL = ("deepseek", "deepseek-chat")


def _usd(micro: float | None) -> str:
    return "—" if micro is None else f"${micro / 1_000_000:.4f}"


async def report(days: int) -> str:
    since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
    async with async_session() as db:
        rows = (
            await db.execute(
                select(
                    AiUsage.source,
                    func.count(AiUsage.id),
                    func.avg(AiUsage.input_tokens), func.avg(AiUsage.output_tokens),
                    func.max(AiUsage.input_tokens), func.max(AiUsage.output_tokens),
                    func.avg(AiUsage.cost_micro_usd),
                    func.count(func.distinct(AiUsage.user_id)),
                )
                .where(AiUsage.created_at >= since)
                .group_by(AiUsage.source)
                .order_by(func.count(AiUsage.id).desc())
            )
        ).all()

    lines = [
        f"# AI cost per feature — last {days} days",
        "",
        "Price is the feature's credit price (1 credit = $0.01). The deepseek columns re-price the",
        "same tokens at deepseek-chat; 'largest' takes the biggest input and output seen.",
        "",
        "| feature | calls | students | avg in | avg out | avg cost (as billed) | avg on deepseek | largest on deepseek | price |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for source, calls, avg_in, avg_out, max_in, max_out, avg_cost, students in rows:
        avg_in, avg_out = float(avg_in or 0), float(avg_out or 0)
        on_deepseek = pricing.estimate_cost_micro_usd(*MODEL, round(avg_in), round(avg_out))
        largest = pricing.estimate_cost_micro_usd(*MODEL, max_in or 0, max_out or 0)
        price = credits.credits_for(source) * credits.CREDIT_PRICE_CENTS * 10_000
        flag = "  ⚠ near or over price" if largest and price and largest > price * 0.8 else ""
        lines.append(
            f"| {source} | {calls} | {students} | {avg_in:.0f} | {avg_out:.0f} | "
            f"{_usd(float(avg_cost) if avg_cost is not None else None)} | {_usd(on_deepseek)} | "
            f"{_usd(largest)} | {credits.credits_for(source)} cr ({_usd(price)}){flag} |"
        )
    if not rows:
        lines.append("| (no AI calls in this period) | | | | | | | | |")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--days", type=int, default=30)
    args = parser.parse_args()
    print(asyncio.run(report(args.days)))


if __name__ == "__main__":
    main()
