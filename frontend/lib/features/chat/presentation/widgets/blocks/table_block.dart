import 'package:flutter/material.dart';

/// Renders a `{"type": "table", "headers": [...], "rows": [[...], ...]}`
/// block — the shape ocr/table_extraction and document_engine/
/// pdf_processing's table detection both produce.
///
/// HONEST GAP: features/moderator/engine.py does not currently route to
/// ocr/table_extraction at all (its routing table only reaches
/// math_engine/symbolic, math_engine/graphing, ocr/text_ocr, and
/// document_engine/searchable_knowledge — see moderator/README.md's list
/// of composed engines). So this widget exists and works, but nothing in
/// the current chat flow can actually trigger a "table" block yet; it's
/// here so the block vocabulary isn't silently unsupported once the
/// moderator's routing is extended, not because it's reachable today.
class TableBlockView extends StatelessWidget {
  const TableBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final headers = (block['headers'] as List<dynamic>?)?.map((h) => h.toString()).toList() ?? [];
    final rows = (block['rows'] as List<dynamic>?) ?? [];

    if (headers.isEmpty && rows.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('(empty table)'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [for (final h in headers) DataColumn(label: Text(h))],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [for (final cell in (row as List<dynamic>)) DataCell(Text(cell.toString()))],
              ),
          ],
        ),
      ),
    );
  }
}
