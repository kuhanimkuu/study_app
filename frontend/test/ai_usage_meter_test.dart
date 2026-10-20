// The token meter (2026-10-20): Profile's "AI usage" card summarises this
// month, its screen shows each period and model, an unpriced model says
// "no price" instead of a made-up $0, the estimate disclaimer is always
// there, and the student's own monthly limit can be set and shows a bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/features/account/presentation/widgets/ai_usage_meter.dart';

Map<String, dynamic> _period(int calls, int input, int output, int cost, int unpriced) => {
      'calls': calls,
      'input_tokens': input,
      'output_tokens': output,
      'cost_micro_usd': cost,
      'unpriced_calls': unpriced,
    };

class _FakeApi extends ApiClient {
  _FakeApi({this.limitCents, this.monthCost = 4200}) : super(baseUrl: 'http://test');

  int? limitCents;
  final int monthCost;
  final List<int?> limitWrites = [];

  @override
  Future<Map<String, dynamic>> getAiUsage() async => {
        'today': _period(1, 2000, 500, 600, 0),
        'this_month': _period(3, 12000, 3000, monthCost, 1),
        'last_30_days': _period(3, 12000, 3000, monthCost, 1),
        'all_time': _period(3, 12000, 3000, monthCost, 1),
        'by_model': [
          {'provider': 'openai', 'model_name': 'gpt-4o-mini', 'hosted': false, 'calls': 2, 'input_tokens': 11990, 'output_tokens': 2990, 'cost_micro_usd': monthCost},
          {'provider': 'openai', 'model_name': 'custom-x', 'hosted': false, 'calls': 1, 'input_tokens': 10, 'output_tokens': 10, 'cost_micro_usd': null},
        ],
        'monthly_limit_cents': limitCents,
      };

  @override
  Future<Map<String, dynamic>> setAiSpendLimit(int? monthlyLimitCents) async {
    limitWrites.add(monthlyLimitCents);
    limitCents = monthlyLimitCents;
    return {'monthly_limit_cents': monthlyLimitCents};
  }
}

void main() {
  test('formats tokens and small costs without rounding to free', () {
    expect(formatTokens(950), '950');
    expect(formatTokens(15000), '15K');
    expect(formatTokens(2500000), '2.5M');
    expect(formatMicroUsd(0), '\$0.00');
    expect(formatMicroUsd(600), '\$0.0006');
    expect(formatMicroUsd(1234567), '\$1.23');
  });

  testWidgets('card summarises the month and opens the full meter', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiUsageMeterCard(apiClient: _FakeApi()))));
    await tester.pumpAndSettle();
    expect(find.text('15K tokens · about \$0.0042 this month'), findsOneWidget);

    await tester.tap(find.text('AI usage'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('gpt-4o-mini'), findsOneWidget);
    expect(find.text('no price'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Prices are estimates'), 200);
    expect(find.textContaining('1 call used a model we don\'t have a price for'), findsOneWidget);
  });

  testWidgets('setting a monthly limit validates, saves it and shows the bar', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: AiUsageScreen(apiClient: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set a limit'));
    await tester.pumpAndSettle();
    for (final bad in ['0', '0.005', 'abc', '5000']) {
      await tester.enterText(find.byType(TextField), bad);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('between'), findsOneWidget, reason: bad);
    }
    expect(api.limitWrites, isEmpty);

    await tester.enterText(find.byType(TextField), '0.01');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.limitWrites, [1]);
    // $0.0042 of $0.01 is 42%: a bar, not yet a warning.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('\$0.0042 of \$0.01 used this month.'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove limit'));
    await tester.pumpAndSettle();
    expect(api.limitWrites, [1, null]);
    expect(find.text('Set a limit'), findsOneWidget);
  });

  testWidgets('warns at 80% and says paid AI is paused once the limit is reached', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AiUsageScreen(apiClient: _FakeApi(limitCents: 1, monthCost: 8500))));
    await tester.pumpAndSettle();
    expect(find.text('Almost there: 85% of your limit used.'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiUsageMeterCard(apiClient: _FakeApi(limitCents: 1, monthCost: 12000)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('reached — paid AI paused'), findsOneWidget);
  });
}
