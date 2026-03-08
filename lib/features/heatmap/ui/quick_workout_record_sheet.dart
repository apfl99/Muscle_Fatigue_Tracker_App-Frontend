import 'package:flutter/material.dart';
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

    setState(() {
      _isSubmitting = true;
    });

    final success = await widget.hook.recordWorkout(
      draft: WorkoutLogDraft(
        exerciseId: selectedExercise.id,
        sets: sets,
        reps: reps,
        weightKg: weight,
        durationMinutes: duration,
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
              left: 16,
              right: 16,
              top: 14,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
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
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '검색 후 종목을 선택하고 바로 저장하세요.',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
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
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '예: 스쿼트, 벤치프레스, 데드리프트',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white70,
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
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
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
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_selectedExercise != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2B22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primaryGreen.withOpacity(0.4),
                        ),
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
                              style: GoogleFonts.poppins(
                                color: Colors.white,
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
                      decoration: BoxDecoration(
                        color: const Color(0xFF181B21),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Colors.white.withOpacity(0.08),
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
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              suggestion.category,
                              style: const TextStyle(color: Colors.white60),
                            ),
                            onTap: () {
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
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '메모 (선택)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: '오늘 운동 컨디션이나 특이사항',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
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
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        (_isSubmitting || widget.hook.isMutating)
                            ? '저장 중...'
                            : '기록 저장',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
