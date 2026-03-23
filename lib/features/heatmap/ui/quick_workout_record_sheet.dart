import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../hook/heatmap_sync_hook.dart';
import '../model/heatmap_models.dart';

class QuickWorkoutRecordSheet extends StatefulWidget {
  const QuickWorkoutRecordSheet({
    super.key,
    required this.hook,
    this.onSaved,
  });

  final HeatmapSyncHook hook;
  final VoidCallback? onSaved;

  @override
  State<QuickWorkoutRecordSheet> createState() =>
      _QuickWorkoutRecordSheetState();
}

class _QuickWorkoutRecordSheetState extends State<QuickWorkoutRecordSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late final TextEditingController _durationController;
  late final TextEditingController _noteController;

  ExerciseSuggestion? _selectedExercise;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _setsController = TextEditingController();
    _repsController = TextEditingController();
    _weightController = TextEditingController();
    _durationController = TextEditingController();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    _durationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveWorkoutLog() async {
    if (_isSubmitting || widget.hook.isMutating) {
      return;
    }
    HapticFeedback.lightImpact();

    final selectedExercise = _selectedExercise;
    if (selectedExercise == null) {
      _showMessage('운동 종목을 선택해주세요.');
      return;
    }

    final sets = _parsePositiveInt(_setsController.text);
    final reps = _parsePositiveInt(_repsController.text);
    final weight = _parseNonNegativeDouble(_weightController.text);
    final duration = _parsePositiveInt(_durationController.text);
    final note = _noteController.text.trim();
    final exerciseType = selectedExercise.exerciseType;

    if (exerciseType == ExerciseType.cardio && duration == null) {
      _showMessage('유산소 운동은 운동 시간(분)을 반드시 입력해주세요.');
      return;
    }

    if (exerciseType == ExerciseType.weight && (sets == null || reps == null)) {
      _showMessage('무산소 운동은 세트 수와 반복 횟수를 반드시 입력해주세요.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final success = await widget.hook.recordWorkout(
      draft: WorkoutLogDraft(
        exerciseId: selectedExercise.id,
        sets: exerciseType == ExerciseType.weight ? sets : null,
        reps: exerciseType == ExerciseType.weight ? reps : null,
        weightKg: exerciseType == ExerciseType.weight ? weight : null,
        durationMinutes: exerciseType == ExerciseType.cardio ? duration : null,
        note: note.isEmpty ? null : note,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      await HapticFeedback.lightImpact();
      if (!mounted) {
        return;
      }
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
      return;
    }

    _showMessage(widget.hook.errorMessage ?? '운동 기록 저장에 실패했습니다.');
  }

  int? _parsePositiveInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  double? _parseNonNegativeDouble(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.hook,
      builder: (context, child) {
        final suggestions = widget.hook.suggestions;
        final hasSearchValue = _searchController.text.trim().isNotEmpty;
        final searchError = widget.hook.searchErrorMessage;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppTheme.pageHorizontalPaddingValue,
              right: AppTheme.pageHorizontalPaddingValue,
              top: 14,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius: AppTheme.buttonRadius,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.fitness_center_outlined,
                        color: AppTheme.primaryGreen,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '빠른 운동 기록',
                        style: GoogleFonts.inter(
                          color: AppTheme.textHigh,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '검색 후 종목을 선택하고 바로 저장하세요.',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMedium,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('quick_record_search_field'),
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _selectedExercise = null;
                      });
                      widget.hook.onSearchKeywordChanged(value);
                    },
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: AppTheme.textHigh),
                    decoration: InputDecoration(
                      hintText: '예: 스쿼트, 벤치프레스, 데드리프트',
                      hintStyle: TextStyle(color: AppTheme.textLow),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppTheme.textMedium,
                      ),
                      suffixIcon: hasSearchValue
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _selectedExercise = null;
                                });
                                widget.hook.clearSearchState();
                              },
                              icon: Icon(
                                Icons.close,
                                color: AppTheme.textMedium,
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.surface2.withValues(alpha: 0.72),
                      border: OutlineInputBorder(
                        borderRadius: AppTheme.buttonRadius,
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppTheme.buttonRadius,
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppTheme.buttonRadius,
                        borderSide: BorderSide(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (widget.hook.isSearchLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (searchError != null && searchError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      searchError,
                      style: GoogleFonts.inter(
                        color: AppTheme.accentDanger,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_selectedExercise != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: AppTheme.cardDecoration(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.10),
                        borderRadius: 14,
                        borderColor:
                            AppTheme.primaryGreen.withValues(alpha: 0.35),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppTheme.primaryGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selectedExercise!.name} (${_selectedExercise!.category})',
                              style: GoogleFonts.inter(
                                color: AppTheme.textHigh,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: AppTheme.cardDecoration(
                        color: AppTheme.surface2.withValues(alpha: 0.50),
                        borderRadius: 16,
                      ),
                      child: ListView.separated(
                        physics: const ClampingScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: AppTheme.borderSubtle,
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = suggestions[index];
                          return ListTile(
                            key: ValueKey(
                              'exercise_suggestion_${suggestion.id}',
                            ),
                            dense: true,
                            title: Text(
                              suggestion.name,
                              style: TextStyle(color: AppTheme.textHigh),
                            ),
                            subtitle: Text(
                              suggestion.category,
                              style: TextStyle(color: AppTheme.textMedium),
                            ),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _selectedExercise = suggestion;
                                _searchController.text = suggestion.name;
                              });
                              widget.hook.clearSearchState();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildNumberField(
                    controller: _setsController,
                    label: '세트 수 (선택)',
                    hint: '예: 4',
                  ),
                  const SizedBox(height: 8),
                  _buildNumberField(
                    controller: _repsController,
                    label: '반복 횟수 (선택)',
                    hint: '예: 12',
                  ),
                  const SizedBox(height: 8),
                  _buildNumberField(
                    controller: _weightController,
                    label: '중량 kg (선택)',
                    hint: '예: 60.5',
                    allowDecimal: true,
                  ),
                  const SizedBox(height: 8),
                  _buildNumberField(
                    controller: _durationController,
                    label: '운동 시간 분 (선택)',
                    hint: '예: 30',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    minLines: 2,
                    maxLines: 3,
                    style: TextStyle(color: AppTheme.textHigh),
                    decoration: InputDecoration(
                      labelText: '메모 (선택)',
                      labelStyle: TextStyle(color: AppTheme.textMedium),
                      hintText: '오늘 운동 컨디션이나 특이사항',
                      hintStyle: TextStyle(color: AppTheme.textLow),
                      filled: true,
                      fillColor: AppTheme.surface2.withValues(alpha: 0.64),
                      border: OutlineInputBorder(
                        borderRadius: AppTheme.buttonRadius,
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppTheme.buttonRadius,
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppTheme.buttonRadius,
                        borderSide: BorderSide(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const ValueKey('quick_record_save_button'),
                      onPressed: (_isSubmitting || widget.hook.isMutating)
                          ? null
                          : _saveWorkoutLog,
                      icon: (_isSubmitting || widget.hook.isMutating)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.ctaOnBrand,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        (_isSubmitting || widget.hook.isMutating)
                            ? '저장 중...'
                            : '기록 저장',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool allowDecimal = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: allowDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      style: TextStyle(color: AppTheme.textHigh),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.textMedium),
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textLow),
        filled: true,
        fillColor: AppTheme.surface2.withValues(alpha: 0.64),
        border: OutlineInputBorder(
          borderRadius: AppTheme.buttonRadius,
          borderSide: BorderSide(color: AppTheme.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTheme.buttonRadius,
          borderSide: BorderSide(color: AppTheme.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTheme.buttonRadius,
          borderSide: BorderSide(
            color: AppTheme.primaryGreen.withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }
}
