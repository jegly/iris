# Iris Play services stubs — how to regenerate (used by patches/apply-android-gms-stubs.sh)
1. out/Android must have been built once with Google's libraries (the header jars
   out/Android/obj/third_party/android_deps/*.ijar.jar), i.e. before google_play_services_package points at the stubs,
   or from a scratch out dir with the default arg.
2. Dump the API: for each Google ijar, `javap -protected -constants -cp <jar> <classes>` into ~/.buildtmp/item9/javap/.
3. roots.txt = every com.google.* class Chromium's non-test Java uses (imports + fully qualified names).
4. `python3 parse.py` (closure -> model.json), `python3 gen.py <out>/src`, copy IrisTasks.java into
   <out>/src/com/google/android/gms/tasks/, then into patches/src/third_party/iris_gms_stubs/java/src and regenerate
   the BUILD.gn source list.
5. Check: javac the Chromium users against the stubs (0 errors), then the real Android build.
Paths inside parse.py/gen.py point at ~/.buildtmp/item9 (scratch); adjust if needed.
