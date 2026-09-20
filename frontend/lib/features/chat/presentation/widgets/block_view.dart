import 'package:flutter/material.dart';

import 'blocks/animation_block.dart';
import 'blocks/clarification_block.dart';
import 'blocks/equation_block.dart';
import 'blocks/error_block.dart';
import 'blocks/graph_block.dart';
import 'blocks/model3d_block.dart';
import 'blocks/model_unavailable_block.dart';
import 'blocks/pdf_block.dart';
import 'blocks/source_block.dart';
import 'blocks/static_image_block.dart';
import 'blocks/table_block.dart';
import 'blocks/text_block.dart';
import 'blocks/unknown_block.dart';

/// Renders one response block (json.md Shape 5 / server/README.md) by
/// dispatching on `block['type']` through `_renderers`. Adding support for
/// a new block type means adding one file under blocks/ and one line to
/// this map — not editing a growing switch statement.
///
/// `baseUrl` is needed by any block whose content is a "/generated/FILENAME"
/// URL path (static_image, animation, 3d, pdf) rather than inline data —
/// see moderator/engine.py's _GENERATED_DIR doc comment for why the server
/// serves these at that path instead of the block carrying a bare local
/// filesystem path.
///
/// Block types with a real renderer today: text, equation,
/// interactive_graph, source, clarification, error, model_unavailable,
/// table, static_image, animation. `3d`/`pdf` get an honest reference card (file is real and
/// fetchable, just no inline 3D/PDF viewer package added yet). `diagram`
/// and anything else in json.md's vocabulary still falls back to
/// UnknownBlockView — a real engine exists behind `diagram`
/// (visual_explanation/diagrams) but no widget renders its shape yet;
/// documented, not silently papered over.
class BlockView extends StatelessWidget {
  const BlockView({super.key, required this.block, required this.baseUrl, this.onSetUpByok});

  final Map<String, dynamic> block;
  final String baseUrl;

  /// Only used by `model_unavailable` — see that block's own doc comment.
  /// Null on any host screen that can't build a route into Account
  /// settings (no AuthService in scope); that block hides its button.
  final VoidCallback? onSetUpByok;

  static final Map<String, Widget Function(Map<String, dynamic> block, String baseUrl, VoidCallback? onSetUpByok)>
      _renderers = {
    'text': (b, _, __) => TextBlockView(block: b),
    'equation': (b, _, __) => EquationBlockView(block: b),
    'interactive_graph': (b, _, __) => GraphBlockView(block: b),
    'source': (b, _, __) => SourceBlockView(block: b),
    'clarification': (b, _, __) => ClarificationBlockView(block: b),
    'error': (b, _, __) => ErrorBlockView(block: b),
    'model_unavailable': (b, _, cb) => ModelUnavailableBlockView(block: b, onSetUpByok: cb),
    'table': (b, _, __) => TableBlockView(block: b),
    'static_image': (b, url, __) => StaticImageBlockView(block: b, baseUrl: url),
    'animation': (b, url, __) => AnimationBlockView(block: b, baseUrl: url),
    '3d': (b, url, __) => Model3dBlockView(block: b, baseUrl: url),
    'pdf': (b, url, __) => PdfBlockView(block: b, baseUrl: url),
  };

  @override
  Widget build(BuildContext context) {
    final renderer = _renderers[block['type']];
    if (renderer != null) return renderer(block, baseUrl, onSetUpByok);
    return UnknownBlockView(block: block);
  }
}
