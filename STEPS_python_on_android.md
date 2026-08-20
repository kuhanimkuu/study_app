# Making Python Run Inside Your Flutter Android App

**Goal:** Get the smallest possible "spine" working — tap a button in Flutter, run a Python
function on the phone, and show the result back in Flutter.

This is the single most important milestone for the whole Study OS project. Everything else
(math engine, OCR, orchestrator, local LLM) is just more Python plugged into this same pipe.

---

## 0. What you are actually building

```
[Flutter UI (Dart)]  ──MethodChannel──►  [Kotlin bridge]  ──Chaquopy──►  [CPython running your .py]
      ▲                                                                              │
      └────────────────────── result comes back the same way ◄────────────────────────┘
```

- **Flutter/Dart** — the button and the text on screen.
- **Kotlin** — the glue that receives a Dart call and hands it to Python.
- **Chaquopy** — the Gradle plugin that bundles a CPython interpreter into the app + gives you
  the `Python.getInstance()` API to call it.
- **Your `.py` file** — ordinary Python. Nothing special about it.

---

## 1. Prerequisites (one-time, do before anything else)

You need the Android build toolchain. Flutter alone is not enough.

1. **Flutter SDK** installed and working.
   - Check: `flutter doctor -v` — it must show no red errors for the Android section.
2. **Android Studio** installed (needed for the Android SDK + NDK).
3. **Android SDK** — install via Android Studio → Settings → SDK Manager:
   - At least one Android platform (latest stable is fine).
   - **NDK (Side by side)** — Chaquopy builds native components, so the NDK is required.
   - **CMake** (usually auto-installed with NDK).
4. **Java 17 (JDK)** — Android Gradle Plugin 8.x needs JDK 17.
   - `java -version` should show 17.
5. **A real Android phone** with USB debugging on (recommended over the emulator for this
   project, because the end goal is on-device inference on a real phone).
   - Phone: Settings → About phone → tap **Build number** 7 times → back to Settings →
     **Developer options** → enable **USB debugging**.
   - Plug it in, accept the "Allow USB debugging?" prompt.
   - Verify: `adb devices` should list your phone as `device` (not `unauthorized`).

> Note: you do **not** need Python installed on your PC for the Android build — Chaquopy
> downloads its own Python at build time. Having Python on your PC is still useful so you can
> test your `.py` logic in a terminal before it ever touches the phone.

---

## 2. Create the Flutter project

```powershell
flutter create study_os
cd study_os
```

(Or, if you already have a project, use it. The following edits go inside the `android/` folder
of that project.)

---

## 3. Add Chaquopy

> ⚠️ Version numbers below are examples. Chaquopy, the Android Gradle Plugin (AGP), and Kotlin
> all version-lock against each other. **Always check https://chaquo.com/chaquopy/doc/current/
> for the latest Chaquopy version and the AGP version it supports.** If the build complains
> about version conflicts, this is almost always the cause.

### 3a. `android/settings.gradle.kts`

Add the Chaquopy Maven repository, and register the plugin version.

In the `pluginManagement { repositories { ... } }` block, add:

```kotlin
maven { url = uri("https://chaquo.com/maven") }
```

In the `plugins { ... }` block, add (version from chaquo.com):

```kotlin
id("com.chaquo.python") version "16.0.0" apply false
```

### 3b. `android/app/build.gradle.kts`

**Step 1 — apply the plugin.** Add it to the existing `plugins { ... }` block (no version here,
the version comes from settings.gradle.kts):

```kotlin
id("com.chaquo.python")
```

**Step 2 — inside `android { defaultConfig { ... } }`, add the ABIs and the Python config:**

```kotlin
defaultConfig {
    // ...existing lines (applicationId, minSdk, etc.) stay untouched...

    ndk {
        abiFilters += listOf("arm64-v8a", "x86_64")
    }

    python {
        version = "3.12"            // Python version to bundle — see chaquo.com for supported versions
        pip {
            // install("sympy")      // add packages here later; leave empty for now
        }
    }
}
```

Notes:
- `arm64-v8a` = almost all modern phones. `x86_64` = emulator. Keeping both lets you test on both.
- The exact Kotlin-DSL syntax of the `python { }` block can differ slightly between Chaquopy
  versions. If it doesn't compile, cross-check the Chaquopy docs for your version.

---

## 4. Write your first Python file

Create the file `android/app/src/main/python/hello.py`:

```python
import sys

def greet(name):
    return f"Hello, {name}! This ran in Python {sys.version.split()[0]} on Android."
```

That's it. Ordinary Python. The `sys.version` trick proves it's really CPython running on the
phone, not some Dart code pretending.

---

## 5. Add the Kotlin bridge (MethodChannel)

Edit `android/app/src/main/kotlin/<your/package>/MainActivity.kt`
(path will match your package name, e.g. `com/example/study_os/MainActivity.kt`).

Replace its contents with:

```kotlin
package com.example.study_os   // <-- keep YOUR package name

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

class MainActivity : FlutterActivity() {
    private val CHANNEL = "python_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Start the embedded Python interpreter once.
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hello" -> {
                        try {
                            val py = Python.getInstance()
                            val module = py.getModule("hello")          // hello.py
                            val answer = module.callAttr("greet", "from Flutter").toString()
                            result.success(answer)
                        } catch (e: Exception) {
                            result.error("PYTHON_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

What this does:
- `Python.start(AndroidPlatform(this))` — boots the embedded CPython interpreter.
- `py.getModule("hello")` — loads `hello.py`.
- `module.callAttr("greet", "from Flutter")` — calls `greet("from Flutter")` and returns the string.

---

## 6. Call it from Flutter (Dart)

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('python_channel');
  String _message = 'Press the button to run Python on the phone';

  Future<void> _runPython() async {
    try {
      final result = await platform.invokeMethod('hello');
      setState(() => _message = result.toString());
    } on PlatformException catch (e) {
      setState(() => _message = 'Error: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Python on Android')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_message, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _runPython,
              child: const Text('Run Python'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 7. Run it on your phone

```powershell
flutter run
```

Select your device. The **first build will be slow** — Chaquopy downloads the Python runtime and
builds native components. Subsequent builds are faster.

---

## 8. What "success" looks like

Tap **Run Python**. The text on screen changes to something like:

```
Hello, from Flutter! This ran in Python 3.12.x on Android.
```

If you see the Python version string, the **entire spine is proven**:
Flutter → Kotlin → embedded CPython → your `.py` → back to Flutter.

This is the moment to celebrate. Everything in Study OS is now "just add more Python + more
block types."

---

## 9. Troubleshooting / common gotchas

| Symptom | Likely cause / fix |
|---|---|
| Build fails with version errors (AGP/Kotlin/Chaquopy) | Version mismatch. Match Chaquopy version to your AGP per chaquo.com. |
| `NDK not found` or native build error | Install NDK via Android Studio → SDK Manager → SDK Tools → NDK (Side by side). |
| `adb devices` shows `unauthorized` | Accept the USB debugging prompt on the phone. |
| App crashes on start with Python error | Check `adb logcat` (filter `flutter`/`chaquopy`). |
| Editing `hello.py` has no effect | Hot reload does **not** reload Python. Do a full rebuild / `flutter run` restart. |
| Emulator vs phone mismatch | `arm64-v8a` for real phones, `x86_64` for emulator. Keep both ABIs. |
| `Python.isStarted()` / `Python.start` unresolved | Chaquopy plugin not applied in `build.gradle.kts`. Re-check step 3b. |

---

## 10. Alternative: `serious_python` (Flutter-first, no Kotlin bridge)

There is a newer option that cuts out the Kotlin/MethodChannel layer entirely — you call Python
directly from Dart:

```
[Flutter/Dart] ──► serious_python package ──► [embedded CPython + your .py]
```

- `flutter pub add serious_python`
- You write Python files in a source directory, and Dart calls them directly.
- Pros: less ceremony, no Kotlin file to write, pure Flutter/Dart workflow.
- Cons: younger project, API changes faster between versions, less battle-tested than Chaquopy.

Because its API moves quickly, I won't paste exact code here that might be stale — follow its
current README at pub.dev/packages/serious_python.

**Recommendation:** Since the Study OS spec already chose Chaquopy and one of your goals is to
*learn the whole stack*, start with **Chaquopy** (you get to see and understand the Kotlin
bridge, which is exactly the layer serious_python hides from you). Evaluate serious_python later
if the Kotlin bridge ever becomes annoying.

---

## 11. Next step after this works

Do **not** build UI features yet. Next, get your plain Python working on your PC in a terminal
(the math engine with `sympy`), then re-plug it in here by adding `install("sympy")` to the
`pip { }` block and a second MethodChannel method. But first: get `hello.py` on screen.
