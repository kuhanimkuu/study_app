import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// The bottom input row: attachment "+" button, a pill-shaped text field
/// (mic inside it), and a round send button that turns solid blue — chunky,
/// design v3 — once there's something to send. Purely presentational — ChatScreen owns
/// the controller and the actions the two buttons trigger.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttachmentTap,
    this.focusNode,
    this.onMicTap,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachmentTap;

  /// Lets a caller (e.g. Home's "Ask" quick action) request focus on this
  /// field programmatically. Optional — the field manages its own focus
  /// fine without one.
  final FocusNode? focusNode;

  /// Shows a mic button next to Send when provided — omitted entirely
  /// (not just disabled) if voice input isn't wired up by the caller,
  /// rather than showing a button that does nothing.
  final VoidCallback? onMicTap;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline, width: 1.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RoundButton(
                icon: Icons.add_rounded,
                tooltip: 'Attach a photo, PDF, audio or link',
                color: theme.colorScheme.primaryContainer,
                iconColor: theme.colorScheme.primary,
                onTap: widget.onAttachmentTap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ask Sage anything…',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: theme.colorScheme.outline, width: 1.5)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: theme.colorScheme.outline, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: StudyOsColors.primary, width: 2)),
                    suffixIcon: widget.onMicTap == null
                        ? null
                        : IconButton(
                            icon: Icon(Icons.mic_rounded, color: theme.colorScheme.onSurfaceVariant),
                            onPressed: widget.onMicTap,
                            tooltip: 'Voice input',
                          ),
                  ),
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),
              const SizedBox(width: 8),
              _RoundButton(
                icon: Icons.arrow_upward_rounded,
                tooltip: 'Send',
                color: hasText ? StudyOsColors.primary : theme.colorScheme.surfaceContainerHigh,
                iconColor: hasText ? Colors.white : theme.colorScheme.onSurfaceVariant,
                ledge: hasText ? StudyOsColors.primaryLedge : null,
                onTap: hasText ? widget.onSend : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 46px circle button; with [ledge], the chunky v3 look.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.color, required this.iconColor, required this.onTap, this.ledge});

  final IconData icon;
  final String tooltip;
  final Color color;
  final Color iconColor;
  final Color? ledge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: tooltip,
        // the ledge is painted first, underneath the coloured circle
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: ledge == null ? null : [BoxShadow(color: ledge!, offset: const Offset(0, 3))],
          ),
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 46, height: 46, child: Icon(icon, color: iconColor, size: 24)),
            ),
          ),
        ),
      ),
    );
  }
}
