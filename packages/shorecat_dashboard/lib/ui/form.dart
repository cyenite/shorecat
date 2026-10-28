// Ashlar UI: Form. Copied into your app by `ashlar add form`; it is yours to change.
//
// Built on Form and FormField from Flutter's widgets layer, which keep each field's value
// and run its checks. This file draws each field as a Field with its error under it, and
// sends focus to the first field that is wrong when the form is sent.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'field.dart';
import 'input.dart';

/// Checks for a field's `validator`: each gives the message to show, or null when the
/// value is right. The messages are English; pass your own in other languages.
///
/// ```dart
/// validator: Validate.all([Validate.required(), Validate.email()])
/// ```
abstract final class Validate {
  /// Something must be given: not null, not blank, not an empty list, not false (for a
  /// box that must be ticked).
  static FormFieldValidator<T> required<T>([String message = 'Required.']) =>
      (v) => switch (v) {
        null || false => message,
        String s when s.trim().isEmpty => message,
        Iterable<Object?> i when i.isEmpty => message,
        _ => null,
      };

  static FormFieldValidator<String> minLength(int n, [String? message]) =>
      (v) => (v ?? '').length < n
      ? message ?? 'At least $n character${n == 1 ? '' : 's'}.'
      : null;

  static FormFieldValidator<String> maxLength(int n, [String? message]) =>
      (v) => (v ?? '').length > n
      ? message ?? 'At most $n character${n == 1 ? '' : 's'}.'
      : null;

  /// An email address, when one is given. Pair it with [required] when one must be.
  static FormFieldValidator<String> email([
    String message = 'Enter an email address.',
  ]) => pattern(_email, message);

  /// Text matching [re] in full, when any is given.
  static FormFieldValidator<String> pattern(RegExp re, String message) =>
      (v) => v == null || v.isEmpty || re.hasMatch(v) ? null : message;

  static FormFieldValidator<num> min(num least, [String? message]) =>
      (v) => v != null && v < least ? message ?? 'At least $least.' : null;

  static FormFieldValidator<num> max(num most, [String? message]) =>
      (v) => v != null && v > most ? message ?? 'At most $most.' : null;

  /// Each check in turn; the first message wins.
  static FormFieldValidator<T> all<T>(List<FormFieldValidator<T>> checks) =>
      (v) {
        for (final check in checks) {
          final message = check(v);
          if (message != null) return message;
        }
        return null;
      };

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
}

/// A field of a [Form], drawn as a [Field]: its label, a description and, once it has
/// been checked, its error. [builder] makes the control from the field's state: give it
/// `field.value`, report changes with `field.didChange`, and mark it with
/// `field.hasError`.
///
/// Errors appear when the form is sent ([FormSend.submit]) and, after that, clear as each
/// one is put right.
///
/// ```dart
/// FormItem<bool>(
///   initialValue: false,
///   axis: Axis.horizontal,
///   label: Text('Accept the terms'),
///   validator: Validate.required('Accept the terms to go on.'),
///   builder: (field) => Checkbox(value: field.value!, error: field.hasError, onChanged: field.didChange),
/// )
/// ```
class FormItem<T> extends FormField<T> {
  FormItem({
    super.key,
    required Widget Function(FormItemState<T> field) builder,
    this.label,
    this.description,
    this.axis = Axis.vertical,
    super.initialValue,
    super.validator,
    super.onSaved,
    super.enabled,
    super.forceErrorText,
    super.restorationId,
    super.autovalidateMode = AutovalidateMode.onUserInteractionIfError,
  }) : super(
         builder: (state) {
           final field = state as FormItemState<T>;
           return Focus(
             focusNode: field._area,
             child: Field(
               axis: axis,
               enabled: field.widget.enabled,
               label: label,
               description: description,
               error: field.hasError ? Text(field.errorText ?? '') : null,
               child: builder(field),
             ),
           );
         },
       );

  /// Above the control, or beside it when across.
  final Widget? label;

  /// Under the control: what the field is for.
  final Widget? description;

  /// Vertical puts the label above (inputs, selects); horizontal puts the control first
  /// (checkboxes, switches).
  final Axis axis;

  @override
  FormItemState<T> createState() => FormItemState<T>();
}

/// The state of a [FormItem]: its value, its error, and [focus] to go to it.
class FormItemState<T> extends FormFieldState<T> {
  // Holds the control's focus without taking any itself, so [focus] can find it.
  final _area = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
    debugLabel: 'FormItem',
  );

  /// Moves focus to the field's control and scrolls it into view.
  void focus() {
    _area.traversalDescendants.firstOrNull?.requestFocus();
    Scrollable.ensureVisible(
      context,
      alignment: .2,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }
}

/// A text field of a [Form]: an [Input] drawn as a [Field], kept in step with the form
/// when it is reset.
///
/// ```dart
/// FormText(
///   label: Text('Email'),
///   placeholder: 'you@example.com',
///   keyboardType: TextInputType.emailAddress,
///   validator: Validate.all([Validate.required(), Validate.email()]),
///   onSaved: (v) => email = v!,
/// )
/// ```
class FormText extends FormItem<String> {
  FormText({
    super.key,
    this.controller,
    String? initialValue,
    super.label,
    super.description,
    String? placeholder,
    Widget? leading,
    Widget? trailing,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? minLines,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    super.validator,
    super.onSaved,
    super.enabled,
    super.forceErrorText,
    super.restorationId,
    super.autovalidateMode,
  }) : super(
         initialValue: controller?.text ?? initialValue ?? '',
         builder: (state) {
           final field = state as _FormTextState;
           return Input(
             controller: field._controller,
             placeholder: placeholder,
             leading: leading,
             trailing: trailing,
             obscureText: obscureText,
             enabled: field.widget.enabled,
             error: field.hasError,
             keyboardType: keyboardType,
             textInputAction: textInputAction,
             autofillHints: autofillHints,
             inputFormatters: inputFormatters,
             maxLines: maxLines,
             minLines: minLines,
             onChanged: (v) {
               field.didChange(v);
               onChanged?.call(v);
             },
             onSubmitted: onSubmitted,
           );
         },
       );

  /// Its text, when you want to read or set it from outside; the field makes one if not.
  final TextEditingController? controller;

  @override
  FormItemState<String> createState() => _FormTextState();
}

class _FormTextState extends FormItemState<String> {
  late final _own = widget.controller == null
      ? TextEditingController(text: widget.initialValue)
      : null;

  TextEditingController get _controller => widget.controller ?? _own!;

  @override
  FormText get widget => super.widget as FormText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_follow);
  }

  // Text set on the controller from outside becomes the field's value.
  void _follow() {
    if (_controller.text != value) super.didChange(_controller.text);
  }

  @override
  void didChange(String? value) {
    super.didChange(value);
    if (_controller.text != value) _controller.text = value ?? '';
  }

  @override
  void reset() {
    // The form's reset puts the first value back; the text follows it.
    _controller.text = widget.initialValue ?? '';
    super.reset();
  }

  @override
  void didUpdateWidget(FormText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_follow);
      _controller.addListener(_follow);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_follow);
    _own?.dispose();
    super.dispose();
  }
}

/// Sending a [Form] the way people expect.
extension FormSend on FormState {
  /// Checks every field. When any is wrong, each shows its error and focus goes to the
  /// first on screen, where a screen reader hears it. When all are right, each field's
  /// `onSaved` runs. Gives whether all were right.
  ///
  /// ```dart
  /// Button(onPressed: () { if (form.currentState!.submit()) send(); }, child: Text('Create'))
  /// ```
  bool submit() {
    final wrong = validateGranularly();
    if (wrong.isEmpty) {
      save();
      return true;
    }
    Offset at(FormFieldState<Object?> f) {
      final box = f.context.findRenderObject() as RenderBox?;
      return box == null || !box.attached
          ? Offset.infinite
          : box.localToGlobal(Offset.zero);
    }

    // Top to bottom, then along the line: from the right in right-to-left text.
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final first =
        (wrong.toList()..sort((a, b) {
              final p = at(a), q = at(b);
              if (p.dy != q.dy) return p.dy.compareTo(q.dy);
              return rtl ? q.dx.compareTo(p.dx) : p.dx.compareTo(q.dx);
            }))
            .whereType<FormItemState<Object?>>()
            .firstOrNull;
    first?.focus();
    return false;
  }
}
