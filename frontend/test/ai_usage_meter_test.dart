// The token meter (2026-10-20): Profile's "AI usage" card summarises the
// last 30 days, its screen shows each period and model, an unpriced model
// says "no price" instead of a made-up $0, and the estimate disclaimer is
// always there.

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
  _FakeApi() : super(baseUrl: 'http://test');

  @override
  Future<Map<String, dynamic>> getAiUsage() async => {
        'today': _period(1, 2000, 500, 600, 0),
        'last_30_days': _period(3, 12000, 3000, 4200, 1),
        'all_time': _period(3, 12000, 3000, 4200, 1),
        'by_model': [
          {'provider': 'openai', 'model_name': 'gpt-4o-mini', 'hosted': false, 'calls': 2, 'input_tokens': 11990, 'output_tokens': 2990, 'cost_micro_usd': 4200},
          {'provider': 'openai', 'model_name': 'custom-x', 'hosted': false, 'calls': 1, 'input_tokens': 10, 'output_tokens': 10, 'cost_micro_usd': null},
        ],
      };
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
    expect(find.text('15K tokens · about \$0.0042 in the last 30 days'), findsOneWidget);

    await tester.tap(find.text('AI usage'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('gpt-4o-mini'), findsOneWidget);
    expect(find.text('no price'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Prices are estimates'), 200);
    expect(find.textContaining('1 call used a model we don\'t have a price for'), findsOneWidget);
  });
}
