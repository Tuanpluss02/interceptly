import 'package:flutter/material.dart';

import '../interceptly_theme.dart';

class InterceptlySearchField extends StatefulWidget {
  const InterceptlySearchField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<InterceptlySearchField> createState() => _InterceptlySearchFieldState();
}

class _InterceptlySearchFieldState extends State<InterceptlySearchField> {
  late TextEditingController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant InterceptlySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;

    _controller.removeListener(_onTextChanged);
    if (_ownsController) {
      _controller.dispose();
    }

    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearText() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;

    return TextField(
      controller: _controller,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
          color: InterceptlyTheme.textMuted,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: InterceptlyTheme.textMuted,
          size: 20,
        ),
        suffixIcon: hasText
            ? IconButton(
                onPressed: _clearText,
                tooltip: 'Clear',
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: InterceptlyTheme.textMuted,
                ),
              )
            : null,
        filled: true,
        fillColor: InterceptlyTheme.surfaceContainer,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: const BorderSide(
            color: InterceptlyTheme.indigo500,
            width: 1.0,
          ),
        ),
      ),
      style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
        color: InterceptlyTheme.textSecondary,
      ),
    );
  }
}

class InterceptlyLabeledTextField extends StatelessWidget {
  const InterceptlyLabeledTextField({
    super.key,
    required this.controller,
    required this.label,
    this.minLines,
    this.maxLines,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final int? minLines;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: InterceptlyTheme.typography.bodyMediumRegular
            .copyWith(color: InterceptlyTheme.textMuted),
      ),
      style: InterceptlyTheme.typography.bodyMediumRegular
          .copyWith(color: InterceptlyTheme.textPrimary),
    );
  }
}
