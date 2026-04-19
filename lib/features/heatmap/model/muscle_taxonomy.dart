const Set<String> canonicalDetailedMuscleCodes = {
  'pectoralis_major_upper',
  'pectoralis_major_sternal',
  'pectoralis_major_lower',
  'pectoralis_minor',
  'deltoid_anterior',
  'deltoid_lateral',
  'deltoid_posterior',
  'rotator_cuff',
  'latissimus_dorsi',
  'trapezius_upper',
  'trapezius_middle',
  'trapezius_lower',
  'teres_major',
  'rhomboids',
  'erector_spinae',
  'biceps_long_head',
  'biceps_short_head',
  'brachialis',
  'triceps_long_head',
  'triceps_lateral_head',
  'triceps_medial_head',
  'forearm_flexors',
  'forearm_extensors',
  'rectus_abdominis',
  'external_obliques',
  'serratus_anterior',
  'rectus_femoris',
  'vastus_lateralis',
  'vastus_medialis',
  'gluteus_maximus',
  'gluteus_medius',
  'biceps_femoris',
  'semitendinosus',
  'gastrocnemius',
  'soleus',
  'tibialis_anterior',
};

const Map<String, String> canonicalLegacyAliasToTarget = {
  'pectoralis_major_clavicular': 'pectoralis_major_upper',
  'pectoralis_major_sternocostal': 'pectoralis_major_sternal',
  'pectoralis_major_abdominal': 'pectoralis_major_lower',
  'trapezius_descending': 'trapezius_upper',
  'trapezius_transverse': 'trapezius_middle',
  'trapezius_ascending': 'trapezius_lower',
  'biceps_brachii_long_head': 'biceps_long_head',
  'biceps_brachii_short_head': 'biceps_short_head',
  'triceps_brachii_long_head': 'triceps_long_head',
  'triceps_brachii_lateral_head': 'triceps_lateral_head',
  'triceps_brachii_medial_head': 'triceps_medial_head',
  'forearm_flexor': 'forearm_flexors',
  'forearm_extensor': 'forearm_extensors',
  'external_oblique': 'external_obliques',
  'gastrocnemius_medial_head': 'gastrocnemius',
  'gastrocnemius_lateral_head': 'gastrocnemius',
  'biceps_femoris_long_head': 'biceps_femoris',
  'biceps_femoris_short_head': 'biceps_femoris',
};

const Set<String> _muscleSideTokens = {
  'left',
  'right',
  'l',
  'r',
  'lt',
  'rt',
  'lhs',
  'rhs',
};

String normalizeCanonicalMuscleCode(String? raw, {bool preferDetailed = true}) {
  if (raw == null) {
    return '';
  }
  var normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  normalized = normalized.replaceAll(RegExp(r'[\s\-./]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'_+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  if (normalized.endsWith('_muscle')) {
    normalized = normalized.substring(0, normalized.length - '_muscle'.length);
  }

  final tokens =
      normalized.split('_').where((token) => token.trim().isNotEmpty).toList();
  if (tokens.length > 1 && _muscleSideTokens.contains(tokens.first)) {
    tokens.removeAt(0);
  }
  if (tokens.length > 1 && _muscleSideTokens.contains(tokens.last)) {
    tokens.removeLast();
  }
  final compact = tokens.join('_');
  if (compact.isEmpty) {
    return '';
  }

  if (canonicalDetailedMuscleCodes.contains(compact)) {
    return compact;
  }

  final target = canonicalLegacyAliasToTarget[compact];
  if (target == null || target.isEmpty) {
    return '';
  }
  if (canonicalDetailedMuscleCodes.contains(target)) {
    return target;
  }
  return '';
}

List<String> expandToDetailedMuscleCodes(String? raw) {
  final normalized = normalizeCanonicalMuscleCode(raw, preferDetailed: true);
  if (normalized.isEmpty) {
    return const <String>[];
  }
  if (canonicalDetailedMuscleCodes.contains(normalized)) {
    return <String>[normalized];
  }
  return const <String>[];
}

String? resolveCanonicalParentGroup(String? raw) {
  final normalized = normalizeCanonicalMuscleCode(raw, preferDetailed: true);
  if (normalized.isEmpty ||
      !canonicalDetailedMuscleCodes.contains(normalized)) {
    return null;
  }
  return null;
}
