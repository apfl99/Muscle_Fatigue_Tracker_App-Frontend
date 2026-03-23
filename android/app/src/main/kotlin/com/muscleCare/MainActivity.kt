package com.muscleCare

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode

class MainActivity : FlutterActivity() {
  // Samsung/OneUI 단말에서 SurfaceView 기반 렌더링 시
  // ViewRootImpl cancelDraw 로그가 과도하게 발생하는 케이스를 완화한다.
  override fun getRenderMode(): RenderMode = RenderMode.texture

  override fun getTransparencyMode(): TransparencyMode = TransparencyMode.opaque
}
