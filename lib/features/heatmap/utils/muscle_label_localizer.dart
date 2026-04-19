import 'package:easy_localization/easy_localization.dart';

import '../model/muscle_taxonomy.dart';

class MuscleLabelLocalizer {
  const MuscleLabelLocalizer._();

  static String homeHeroDisplayName(String muscleCode) {
    final normalized = _normalizeHomeHeroMuscleCode(muscleCode);
    if (normalized.isEmpty) {
      return 'muscle.fullBody'.tr();
    }

    final mappedKey = _homeHeroMuscleNameByCode[normalized];
    if (mappedKey != null) {
      return mappedKey.tr();
    }

    final dynamicKey = 'muscle.${_snakeToCamelCase(normalized)}';
    final dynamicTranslated = dynamicKey.tr();
    if (dynamicTranslated != dynamicKey) {
      return dynamicTranslated;
    }

    return 'muscle.unknown'.tr();
  }

  static String detailedDisplayName(String rawCode) {
    final canonical = normalizeCanonicalMuscleCode(rawCode);
    if (canonical.isEmpty) {
      return 'muscle.unknown'.tr();
    }

    final displayKey = _detailedMuscleDisplayNameMap[canonical];
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

  static String _normalizeHomeHeroMuscleCode(String muscleCode) {
    final normalized = muscleCode.trim().toLowerCase();
    if (normalized.isEmpty) {
      return normalized;
    }
    return _homeHeroMuscleAliases[normalized] ?? normalized;
  }

  static String _snakeToCamelCase(String value) {
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

const Map<String, String> _homeHeroMuscleNameByCode = {
  'chest': 'muscle.chest',
  'pectoralis_major': 'muscle.chest',
  'front_deltoid': 'muscle.frontDeltoid',
  'lateral_deltoid': 'muscle.lateralDeltoid',
  'rear_deltoid': 'muscle.rearDeltoid',
  'biceps': 'muscle.biceps',
  'triceps': 'muscle.triceps',
  'forearms': 'muscle.forearms',
  'forearm_flexor': 'muscle.forearmFlexor',
  'forearm_extensor': 'muscle.forearmExtensor',
  'latissimus': 'muscle.latissimus',
  'trapezius': 'muscle.trapezius',
  'quadriceps': 'muscle.quadriceps',
  'hamstrings': 'muscle.hamstrings',
  'glutes': 'muscle.glutes',
  'calves': 'muscle.calves',
  'rectus_abdominis': 'muscle.rectusAbdominis',
  'obliques': 'muscle.obliques',
};

const Map<String, String> _homeHeroMuscleAliases = {
  'pecs': 'chest',
  'pectoralis_minor': 'chest',
  'anterior_deltoid': 'front_deltoid',
  'front_delts': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'side_deltoid': 'lateral_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'rear_delts': 'rear_deltoid',
  'biceps_brachii': 'biceps',
  'triceps_brachii': 'triceps',
  'forearm': 'forearms',
  'fore_arm': 'forearms',
  'wrist_flexor': 'forearm_flexor',
  'wrist_extensor': 'forearm_extensor',
  'latissimus_dorsi': 'latissimus',
  'lats': 'latissimus',
  'quads': 'quadriceps',
  'abs': 'rectus_abdominis',
  'abdominals': 'rectus_abdominis',
};

const Map<String, String> _detailedMuscleDisplayNameMap = {
  'pectoralis_major_upper': 'muscle.pectoralisMajorUpper',
  'pectoralis_major_sternal': 'muscle.pectoralisMajorSternal',
  'pectoralis_major_lower': 'muscle.pectoralisMajorLower',
  'pectoralis_minor': 'muscle.pectoralisMinor',
  'serratus_anterior': 'muscle.serratusAnterior',
  'deltoid_anterior': 'muscle.frontDeltoid',
  'deltoid_lateral': 'muscle.lateralDeltoid',
  'deltoid_posterior': 'muscle.rearDeltoid',
  'rotator_cuff': 'muscle.rotatorCuff',
  'trapezius_upper': 'muscle.trapeziusUpper',
  'trapezius_middle': 'muscle.trapeziusMiddle',
  'trapezius_lower': 'muscle.trapeziusLower',
  'biceps_long_head': 'muscle.bicepsLongHead',
  'biceps_short_head': 'muscle.bicepsShortHead',
  'brachialis': 'muscle.brachialis',
  'triceps_long_head': 'muscle.tricepsLongHead',
  'triceps_lateral_head': 'muscle.tricepsLateralHead',
  'triceps_medial_head': 'muscle.tricepsMedialHead',
  'forearm_flexors': 'muscle.forearmFlexors',
  'forearm_extensors': 'muscle.forearmExtensors',
  'rectus_abdominis': 'muscle.rectusAbdominis',
  'external_obliques': 'muscle.externalObliques',
  'rectus_femoris': 'muscle.rectusFemoris',
  'vastus_lateralis': 'muscle.vastusLateralis',
  'vastus_medialis': 'muscle.vastusMedialis',
  'biceps_femoris': 'muscle.bicepsFemoris',
  'semitendinosus': 'muscle.semitendinosus',
  'tibialis_anterior': 'muscle.tibialisAnterior',
  'gastrocnemius': 'muscle.gastrocnemius',
  'soleus': 'muscle.soleus',
  'gluteus_maximus': 'muscle.gluteusMaximus',
  'gluteus_medius': 'muscle.gluteusMedius',
  'latissimus_dorsi': 'muscle.latissimus',
  'teres_major': 'muscle.teresMajor',
  'erector_spinae': 'muscle.erectorSpinae',
  'rhomboids': 'muscle.rhomboids',
};
