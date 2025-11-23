/// 광고 관련 상수 정의
class AdConstants {
  // ===== 테스트 광고 ID (Google AdMob 테스트 광고) =====
  static const String testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String testAppOpen = 'ca-app-pub-3940256099942544/3419835294';
  static const String testAndroidBanner =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testIoSBanner = 'ca-app-pub-3940256099942544/2934735716';

  // ===== 실제 릴리즈 모드 광고 ID =====
  // TODO: 실제 광고 ID로 변경하세요

  // Android 광고 ID
  static const String releaseAndroidInterstitial =
      'ca-app-pub-8223579217523211/4144392628';
  static const String releaseAndroidBanner =
      'ca-app-pub-8223579217523211/5705594142';

  // iOS 광고 ID
  static const String releaseIosInterstitial =
      'ca-app-pub-8223579217523211/5925088595';
  static const String releaseIosBanner =
      'ca-app-pub-8223579217523211/6730917115';

  // ===== 하위 호환성 유지 (deprecated) =====
  // @deprecated: 개별 상수들로 분리됨
  static const String releaseAndroidAdMob = releaseAndroidInterstitial;
  static const String releaseIosAdMob = releaseIosInterstitial;
}
