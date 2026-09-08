import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Renders a `{"type": "interactive_graph", "data": {"x": [...], "y": [...]},
/// "latex": "...", "source": "graphing"}` block.
///
/// The moderator (features/moderator/engine.py) sets `"data": result["points"]`
/// where `result` is math_engine/graphing's own output — that engine
/// returns `{"points": {"x": [...], "y": [...]}, "latex": ...}`, so
/// `result["points"]` is `{"x": [...], "y": [...]}` directly. `data` here
/// therefore already IS the points map — `data["x"]`/`data["y"]`, not
/// `data["points"]["x"]`. An earlier version of this widget assumed the
/// nested shape and would have silently rendered nothing for every real
/// graph response; caught by re-checking against the actual verified
/// server output (curl output logged earlier in this session) rather than
/// the shape assumed from memory.
class GraphBlockView extends StatelessWidget {
  const GraphBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final data = block['data'] as Map<String, dynamic>?;
    final xs = (data?['x'] as List<dynamic>?)?.map((v) => (v as num).toDouble()).toList();
    final ys = (data?['y'] as List<dynamic>?)?.map((v) => (v as num).toDouble()).toList();

    if (xs == null || ys == null || xs.isEmpty || xs.length != ys.length) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('(graph data missing or malformed)'),
      );
    }

    final spots = [for (var i = 0; i < xs.length; i++) FlSpot(xs[i], ys[i])];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 220,
        child: LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(spots: spots, isCurved: false, dotData: const FlDotData(show: false)),
            ],
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: true),
            borderData: FlBorderData(show: true),
          ),
        ),
      ),
    );
  }
}
