import 'package:easy_localization/easy_localization.dart';
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
          : 'workoutLog.noteFromAnalysis'.tr(
              namedArgs: {
                'score': widget.bridgePayload!.fatigueScore.toStringAsFixed(2),
              },
            ),
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
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxSheetHeight = mediaQuery.size.height * 0.92;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          decoration: AppTheme.cardDecoration(
            color: AppTheme.surface1,
            borderRadius: 28,
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'workoutLog.title'.tr(),
                        style: AppTheme.titleLargeStyle,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop(false);
                      },
                      icon: Icon(Icons.close, color: AppTheme.textMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSearchField(provider),
                if (provider.searchErrorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    provider.searchErrorMessage!.tr(),
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
                    decoration: AppTheme.cardDecoration(
                      color: AppTheme.surface2.withValues(alpha: 0.46),
                      borderRadius: 16,
                    ),
                    child: Text(
                      'workoutLog.selectExerciseHint'.tr(),
                      style: TextStyle(color: AppTheme.textMedium, height: 1.4),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteController,
                  style: TextStyle(color: AppTheme.textHigh),
                  maxLines: 2,
                  decoration: _inputDecoration(
                    label: 'workoutLog.fields.noteOptional'.tr(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('workout_log_save_button'),
                    onPressed: provider.isSaving
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            _save(provider);
                          },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: provider.isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'workoutLog.save'.tr(),
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
      style: TextStyle(color: AppTheme.textHigh),
      decoration:
          _inputDecoration(label: 'workoutLog.fields.searchExercise'.tr()),
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
        decoration: AppTheme.cardDecoration(
          color: AppTheme.surface2.withValues(alpha: 0.42),
          borderRadius: 16,
        ),
        child: Text(
          'workoutLog.noSearchResult'.tr(),
          style: TextStyle(color: AppTheme.textLow),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface2.withValues(alpha: 0.38),
        borderRadius: 16,
      ),
      child: ListView.separated(
        physics: const ClampingScrollPhysics(),
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => Divider(
          color: AppTheme.borderSubtle,
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
              style: TextStyle(color: AppTheme.textHigh),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${suggestion.category} · ${_exerciseTypeLabel(suggestion.exerciseType)} · ${_muscleSizeLabel(suggestion.muscleSize)}',
                  style: TextStyle(color: AppTheme.textMedium, fontSize: 12),
                ),
                if (_muscleHintText(suggestion).isNotEmpty)
                  Text(
                    _muscleHintText(suggestion),
                    style: TextStyle(color: AppTheme.textLow, fontSize: 11),
                  ),
              ],
            ),
            trailing: selected
                ? const Icon(Icons.check_circle, color: AppTheme.primaryGreen)
                : null,
            onTap: () {
              HapticFeedback.lightImpact();
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
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface2.withValues(alpha: 0.56),
        borderRadius: 16,
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
              style: TextStyle(
                color: AppTheme.textHigh,
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
              label: 'workoutLog.fields.durationRequired'.tr(),
              decimal: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildNumberField(
              controller: _distanceController,
              label: 'workoutLog.fields.distance'.tr(),
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
                label: 'workoutLog.fields.setRequired'.tr(),
                decimal: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNumberField(
                controller: _repsController,
                label: 'workoutLog.fields.repRequired'.tr(),
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
                label: 'workoutLog.fields.weightRequired'.tr(),
                decimal: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNumberField(
                controller: _durationController,
                label: 'workoutLog.fields.duration'.tr(),
                decimal: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildNumberField(
          controller: _distanceController,
          label: 'workoutLog.fields.distance'.tr(),
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
      style: TextStyle(color: AppTheme.textHigh),
      decoration: _inputDecoration(label: label),
    );
  }

  InputDecoration _inputDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textMedium),
      filled: true,
      fillColor: AppTheme.surface2.withValues(alpha: 0.70),
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
    );
  }

  Future<void> _save(HeatmapProvider provider) async {
    final selected = _selectedExercise;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('workoutLog.errors.selectExercise'.tr())),
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
        SnackBar(
          content: Text('workoutLog.errors.cardioDurationRequired'.tr()),
        ),
      );
      return;
    }

    if (_isWeight && (sets == null || reps == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('workoutLog.errors.weightSetRepRequired'.tr())),
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
      await HapticFeedback.lightImpact();
      if (!mounted) {
        return;
      }
      if (provider.lastSaveQueuedOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('offline.syncQueued'.tr())),
        );
      }
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (provider.errorMessage ?? 'workoutLog.errors.saveFailed').tr(),
        ),
      ),
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
        return 'workoutLog.exerciseType.cardio'.tr();
      case ExerciseType.weight:
        return 'workoutLog.exerciseType.weight'.tr();
      case ExerciseType.unknown:
        return 'workoutLog.exerciseType.unknown'.tr();
    }
  }

  String _muscleSizeLabel(MuscleSize size) {
    switch (size) {
      case MuscleSize.large:
        return 'workoutLog.muscleSize.large'.tr();
      case MuscleSize.small:
        return 'workoutLog.muscleSize.small'.tr();
      case MuscleSize.unknown:
        return 'workoutLog.muscleSize.unknown'.tr();
    }
  }

  String _muscleHintText(ExerciseSuggestion suggestion) {
    final primary = _joinMuscleNames(suggestion.primaryMuscles, maxCount: 2);
    final secondary =
        _joinMuscleNames(suggestion.secondaryMuscles, maxCount: 3);
    final sections = <String>[];
    if (primary.isNotEmpty) {
      sections.add('workoutLog.hint.primary'.tr(args: [primary]));
    }
    if (secondary.isNotEmpty) {
      sections.add('workoutLog.hint.secondary'.tr(args: [secondary]));
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
    return hasMore
        ? 'common.andMore'.tr(args: [clipped.join(', ')])
        : clipped.join(', ');
  }

  String _formatMuscleCodeToLabel(String code) {
    final canonical = _normalizeWorkoutMuscleCode(code);
    if (canonical.isEmpty) {
      return 'muscle.unknown'.tr();
    }
    final displayKey = _workoutMuscleDisplayNameMap[canonical];
    if (displayKey != null) {
      return displayKey.tr();
    }

    final dynamicKey = 'muscle.${_snakeToCamelCase(canonical)}';
    final translated = dynamicKey.tr();
    if (translated != dynamicKey) {
      return translated;
    }

    return 'muscle.unknown'.tr();
  }

  String _normalizeWorkoutMuscleCode(String rawCode) {
    var normalized = rawCode.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    normalized = normalized.replaceAll(RegExp(r'[\s\-./]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.endsWith('_muscle')) {
      normalized =
          normalized.substring(0, normalized.length - '_muscle'.length);
    }
    final tokens = normalized
        .split('_')
        .where((token) => token.trim().isNotEmpty)
        .toList();
    if (tokens.length > 1 && _workoutSideTokens.contains(tokens.first)) {
      tokens.removeAt(0);
    }
    if (tokens.length > 1 && _workoutSideTokens.contains(tokens.last)) {
      tokens.removeLast();
    }
    final compact = tokens.join('_');
    if (compact.isEmpty) {
      return '';
    }
    return _workoutMuscleAliases[compact] ?? compact;
  }

  String _snakeToCamelCase(String value) {
    final tokens = value.split('_').where((token) => token.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return value;
    }
    return tokens.first +
        tokens
            .skip(1)
            .map((token) => '${token[0].toUpperCase()}${token.substring(1)}')
            .join();
  }
}

const Set<String> _workoutSideTokens = {
  'left',
  'right',
  'l',
  'r',
  'lt',
  'rt',
  'lhs',
  'rhs',
};

const Map<String, String> _workoutMuscleAliases = {
  'abs': 'rectus_abdominis',
  'abdominals': 'rectus_abdominis',
  'pectoralis_major': 'chest',
  'pectoralis_minor': 'pectoralis_minor',
  'front_delts': 'front_deltoid',
  'anterior_deltoid': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'rear_delts': 'rear_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'quads': 'quadriceps',
  'latissimus_dorsi': 'latissimus',
  'lats': 'latissimus',
  'gastrocnemius_medial': 'gastrocnemius',
  'gastrocnemius_lateral': 'gastrocnemius',
  'spinal_erectors': 'erector_spinae',
  'lumbar': 'lower_back',
  'biceps_brachii': 'biceps',
  'wrist_flexor': 'forearm_flexor',
  'wrist_extensor': 'forearm_extensor',
  'forearm': 'forearms',
  'forearms': 'forearms',
  'triceps_brachii': 'triceps',
  'triceps_surae': 'calves',
  'hamstring': 'hamstrings',
  'adductor': 'adductors',
  'adductors_group': 'adductors',
  'abductor': 'abductors',
  'abductors_group': 'abductors',
  'glute_medius': 'gluteus_medius',
  'glute_maximus': 'gluteus_maximus',
  'glute_minimus': 'gluteus_minimus',
  'latissimus_dorsi_lower': 'latissimus_lower',
  'latissimus_dorsi_upper': 'latissimus_upper',
  'upper_trap': 'trapezius',
  'middle_trap': 'trapezius',
  'lower_trap': 'trapezius',
};

const Map<String, String> _workoutMuscleDisplayNameMap = {
  'neck': 'muscle.neck',
  'chest': 'muscle.chest',
  'pectoralis_minor': 'muscle.pectoralisMinor',
  'serratus_anterior': 'muscle.serratusAnterior',
  'front_deltoid': 'muscle.frontDeltoid',
  'lateral_deltoid': 'muscle.lateralDeltoid',
  'rear_deltoid': 'muscle.rearDeltoid',
  'trapezius': 'muscle.trapezius',
  'biceps': 'muscle.biceps',
  'brachialis': 'muscle.brachialis',
  'triceps': 'muscle.triceps',
  'brachioradialis': 'muscle.brachioradialis',
  'forearm': 'muscle.forearm',
  'forearms': 'muscle.forearms',
  'forearm_flexor': 'muscle.forearmFlexor',
  'forearm_extensor': 'muscle.forearmExtensor',
  'rectus_abdominis': 'muscle.rectusAbdominis',
  'obliques': 'muscle.obliques',
  'hip_flexor': 'muscle.hipFlexor',
  'adductors': 'muscle.adductors',
  'adductor_longus': 'muscle.adductorLongus',
  'adductor_brevis': 'muscle.adductorBrevis',
  'adductor_magnus': 'muscle.adductorMagnus',
  'abductors': 'muscle.abductors',
  'quadriceps': 'muscle.quadriceps',
  'rectus_femoris': 'muscle.rectusFemoris',
  'vastus_lateralis': 'muscle.vastusLateralis',
  'vastus_medialis': 'muscle.vastusMedialis',
  'vastus_intermedius': 'muscle.vastusIntermedius',
  'hamstrings': 'muscle.hamstrings',
  'biceps_femoris': 'muscle.bicepsFemoris',
  'semitendinosus': 'muscle.semitendinosus',
  'semimembranosus': 'muscle.semimembranosus',
  'tibialis_anterior': 'muscle.tibialisAnterior',
  'calves': 'muscle.calves',
  'gastrocnemius': 'muscle.gastrocnemius',
  'soleus': 'muscle.soleus',
  'glutes': 'muscle.glutes',
  'gluteus_maximus': 'muscle.gluteusMaximus',
  'gluteus_medius': 'muscle.gluteusMedius',
  'gluteus_minimus': 'muscle.gluteusMinimus',
  'latissimus': 'muscle.latissimus',
  'latissimus_lower': 'muscle.latissimusLower',
  'latissimus_upper': 'muscle.latissimusUpper',
  'teres_major': 'muscle.teresMajor',
  'teres_minor': 'muscle.teresMinor',
  'infraspinatus': 'muscle.infraspinatus',
  'supraspinatus': 'muscle.supraspinatus',
  'subscapularis': 'muscle.subscapularis',
  'erector_spinae': 'muscle.erectorSpinae',
  'lower_back': 'muscle.lowerBack',
};
