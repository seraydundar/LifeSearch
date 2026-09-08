package com.lifesearch.lifesearch

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's Android implementation needs a FragmentActivity host
// (it shows the biometric prompt as a DialogFragment) — a plain
// FlutterActivity crashes with a ClassCastException at runtime.
class MainActivity : FlutterFragmentActivity()
