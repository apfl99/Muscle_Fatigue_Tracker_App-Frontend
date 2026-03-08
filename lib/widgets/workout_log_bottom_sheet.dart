import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../providers/heatmap_provider.dart';
import '../theme/app_theme.dart';

class WorkoutLogBottomSheet extends StatefulWidget {
  const WorkoutLogBottomSheet({
    super.key,
    this.bridgePayload,
  });

  final MeasurementBridgePayload? bridgePayload;

  @override
  State<WorkoutLogBottomSheet> createState() => _WorkoutLogBottomSheetState();
}

class _WorkoutLogBottomSheetState extends State<WorkoutLogBottomSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late final TextEditingController _durationController;
  late final TextEditingController _distanceController;
  late final TextEditingController _noteController;
  late final FocusNode _searchFocusNode;

  ExerciseSuggestion? _selectedExercise;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _setsController = TextEditingController();
    _repsController = TextEditingController();
    _weightController = TextEditingController();
    _durationController = TextEditingController();
    _distanceController = TextEditingController();
    _noteController = TextEditingController(
      text: widget.bridgePayload == null
          ? ''
          : '정밀 분석 점수 ${widget.bridgePayload!.fatigueScore.toStringAsFixed(2)} 기반으로 기록',
    );
    _searchFocusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    _durationController.dispose();
    _distanceController.dispose();
    _noteController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HeatmapProvider>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 20,
                offset: Offset(0, -8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '오늘의 컨디션 로그',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSearchField(provider),
                if (provider.searchErrorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    provider.searchErrorMessage!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                _buildSuggestions(provider),
                const SizedBox(height: 14),
                if (_selectedExercise != null) ...[
                  _buildExerciseInfoCard(_selectedExercise!),
                  const SizedBox(height: 10),
                  _buildDynamicInputFields(),
                ] else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '운동 종목을 선택하면 유형별 입력 폼이 자동으로 열립니다.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: _inputDecoration(label: '메모(선택)'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('workout_log_save_button'),
                    onPressed: provider.isSaving ? null : () => _save(provider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: provider.isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '운동 볼륨 저장',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(HeatmapProvider provider) {
    return TextField(
      key: const Key('workout_search_field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      onChanged: (value) {
        _selectedExercise = null;
        provider.onSearchKeywordChanged(value);
        setState(() {});
      },
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label: '운동 종목 검색'),
    );
  }

  bool get _isCardio => _selectedExercise?.exerciseType == ExerciseType.cardio;

  bool get _isWeight => !_isCardio;

  Widget _buildSuggestions(HeatmapProvider provider) {
    final suggestions = provider.exerciseSuggestions;

    if (_searchController.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    if (provider.isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '검색 결과가 없습니다.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => Divider(
          color: Colors.white.withValues(alpha: 0.1),
          height: 1,
        ),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final selected = _selectedExercise?.id == suggestion.id;
          return ListTile(
            key: Key('exercise_suggestion_${suggestion.id}'),
            dense: true,
            selected: selected,
            selectedColor: AppTheme.primaryGreen,
            title: Text(
              suggestion.name,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${suggestion.category} · ${_exerciseTypeLabel(suggestion.exerciseType)} · ${_muscleSizeLabel(suggestion.muscleSize)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (_muscleHintText(suggestion).isNotEmpty)
                  Text(
                    _muscleHintText(suggestion),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
            trailing: selected
                ? const Icon(Icons.check_circle, color: AppTheme.primaryGreen)
                : null,
            onTap: () {
              setState(() {
                _selectedExercise = suggestion;
                _searchController.text = suggestion.name;
                if (suggestion.exerciseType == ExerciseType.cardio) {
                  _setsController.clear();
                  _repsController.clear();
                  _weightController.clear();
                }
              });
              provider.clearSearchState();
            },
          );
        },
      ),
    );
  }

  Widget _buildExerciseInfoCard(ExerciseSuggestion suggestion) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
              [
                '${suggestion.name} · ${_exerciseTypeLabel(suggestion.exerciseType)} · ${_muscleSizeLabel(suggestion.muscleSize)}',
                _muscleHintText(suggestion),
              ].where((line) => line.trim().isNotEmpty).join('\n'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicInputFields() {
    if (_isCardio) {
      return Row(
        children: [
          Expanded(
            child: _buildNumberField(
              controller: _durationController,
              label: '운동 시간(분) *',
              decimal: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildNumberField(
              controller: _distanceController,
              label: '이동 거리(km)',
              decimal: true,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildNumberField(
                controller: _setsController,
                label: '세트 *',
                decimal: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNumberField(
                controller: _repsController,
                label: '횟수 *',
                decimal: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildNumberField(
                controller: _weightController,
                label: '중량(kg) *',
                decimal: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNumberField(
                controller: _durationController,
                label: '운동 시간(분)',
                decimal: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildNumberField(
          controller: _distanceController,
          label: '이동 거리(km)',
          decimal: true,
        ),
      ],
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required bool decimal,
  }) {
    return TextField(
      controller: controller,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label: label),
    );
  }

  InputDecoration _inputDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.primaryGreen),
      ),
    );
  }

  Future<void> _save(HeatmapProvider provider) async {
    final selected = _selectedExercise;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('운동 종목을 선택해 주세요.')),
      );
      return;
    }

    final sets = _tryParseInt(_setsController.text);
    final reps = _tryParseInt(_repsController.text);
    final weightKg = _tryParseDouble(_weightController.text);
    final durationMinutes = _tryParseInt(_durationController.text);
    final distanceKm = _tryParseDouble(_distanceController.text);

    if (_isCardio && durationMinutes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유산소 운동은 진행 시간(분)을 반드시 입력해 주세요.')),
      );
      return;
    }

    if (_isWeight && (sets == null || reps == null || weightKg == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('무산소 운동은 세트/횟수/중량을 모두 입력해 주세요.')),
      );
      return;
    }

    final success = await provider.saveWorkoutLog(
      draft: WorkoutLogDraft(
        exerciseId: selected.id,
        sets: _isWeight ? sets : null,
        reps: _isWeight ? reps : null,
        weightKg: _isWeight ? weightKg : null,
        durationMinutes: durationMinutes,
        distanceKm: distanceKm,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );

    if (!mounted) {
      return;
    }

    if (success) {
      await HapticFeedback.mediumImpact();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(provider.errorMessage ?? '기록 저장에 실패했습니다.')),
    );
  }

  int? _tryParseInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  double? _tryParseDouble(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }

  String _exerciseTypeLabel(ExerciseType type) {
    switch (type) {
      case ExerciseType.cardio:
        return '유산소';
      case ExerciseType.weight:
        return '무산소';
      case ExerciseType.unknown:
        return '기타';
    }
  }

  String _muscleSizeLabel(MuscleSize size) {
    switch (size) {
      case MuscleSize.large:
        return '대근육';
      case MuscleSize.small:
        return '소근육';
      case MuscleSize.unknown:
        return '근육 크기 미상';
    }
  }

  String _muscleHintText(ExerciseSuggestion suggestion) {
    final primary = _joinMuscleNames(suggestion.primaryMuscles, maxCount: 2);
    final secondary =
        _joinMuscleNames(suggestion.secondaryMuscles, maxCount: 3);
    final sections = <String>[];
    if (primary.isNotEmpty) {
      sections.add('주동근: $primary');
    }
    if (secondary.isNotEmpty) {
      sections.add('협응근: $secondary');
    }
    return sections.join(' · ');
  }

  String _joinMuscleNames(List<String> muscles, {required int maxCount}) {
    if (muscles.isEmpty) {
      return '';
    }
    final normalized = muscles
        .map(_formatMuscleCodeToLabel)
        .where((name) => name.isNotEmpty)
        .toList();
    if (normalized.isEmpty) {
      return '';
    }
    final clipped = normalized.take(maxCount).toList();
    final hasMore = normalized.length > clipped.length;
    return hasMore ? '${clipped.join(', ')} 외' : clipped.join(', ');
  }

  String _formatMuscleCodeToLabel(String code) {
    switch (code.trim().toLowerCase()) {
      case 'chest':
      case 'pectoralis_major':
        return '대흉근';
      case 'front_deltoid':
      case 'front_delts':
      case 'anterior_deltoid':
        return '전면 삼각근';
      case 'lateral_deltoid':
      case 'lateral_delts':
        return '측면 삼각근';
      case 'rear_deltoid':
      case 'rear_delts':
      case 'posterior_deltoid':
        return '후면 삼각근';
      case 'quadriceps':
      case 'quads':
        return '대퇴사두근';
      case 'hamstrings':
        return '햄스트링';
      case 'glutes':
      case 'gluteus_maximus':
        return '둔근';
      case 'calves':
      case 'gastrocnemius':
        return '비복근';
      case 'latissimus':
      case 'latissimus_dorsi':
      case 'lats':
        return '광배근';
      case 'lower_back':
      case 'lumbar':
        return '척추기립근';
      case 'rectus_abdominis':
      case 'abs':
        return '복직근';
      case 'obliques':
        return '복사근';
      case 'biceps':
        return '상완이두근';
      case 'triceps':
        return '상완삼두근';
      default:
        return code.trim();
    }
  }
}
