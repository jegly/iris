#!/usr/bin/env bash
# Iris — Phase B4: canvas and audio fingerprint protection (verified against this checkout 2026-09-27).
# New code (patches/src):
#   third_party/blink/public/mojom/iris/iris_fingerprint.mojom   blink.mojom.IrisFingerprintHost [Sync] GetMode()
#   third_party/blink/renderer/core/html/canvas/iris_fingerprint.* Blink helper (per-document Supplement; pixel/audio
#                                                                 changes; see its header for the modes)
#   chrome/browser/iris/iris_fingerprint_host.*                  per-document browser host (mode + per-site seed)
# Hooks: HTMLCanvasElement toDataURL/toBlob, OffscreenCanvas.convertToBlob, CanvasRenderingContext2D.getImageData
# (both overloads), AudioBuffer.getChannelData (JS overload) + copyFromChannel. Frame binder in
# chrome_browser_interface_binders.cc. Settings -> Site settings -> a site -> "Canvas and audio reading" (select;
# SiteSettingsHandler irisGet/SetFingerprintReads). Setting type + strings from apply-iris-permissions.sh.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
put() {
  local from="$DIR/src/$1" to="$1"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  mkdir -p "$(dirname "$to")"
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
}
put third_party/blink/public/mojom/iris/iris_fingerprint.mojom
put third_party/blink/renderer/core/html/canvas/iris_fingerprint.h
put third_party/blink/renderer/core/html/canvas/iris_fingerprint.cc
put chrome/browser/iris/iris_fingerprint_host.h
put chrome/browser/iris/iris_fingerprint_host.cc

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
def add_include(p, after, inc):
    s = open(p).read()
    if inc in s: return
    if s.count(after) != 1: die("%s: include anchor %s not found once" % (p, after))
    open(p, "w").write(s.replace(after, after + inc, 1)); print("OK   %s : include" % p)
if "IDS_SETTINGS_IRIS_FINGERPRINT_READS_REAL" not in open("chrome/app/settings_strings.grdp").read():
    die("strings/type missing: run apply-iris-permissions.sh first")

# --- build lists
edit("third_party/blink/public/mojom/BUILD.gn",
     "mojom(\"mojom_platform\") {\n  generate_blink = true\n  generate_java = true\n  sources = [\n",
     "mojom(\"mojom_platform\") {\n  generate_blink = true\n  generate_java = true\n  sources = [\n"
     "    \"iris/iris_fingerprint.mojom\",  # Iris (B4)\n",
     "iris/iris_fingerprint.mojom", "mojom source")
edit("third_party/blink/renderer/core/html/build.gni",
     "  \"canvas/image_data.h\",\n",
     "  \"canvas/image_data.h\",\n  \"canvas/iris_fingerprint.cc\",  # Iris (B4)\n  \"canvas/iris_fingerprint.h\",\n",
     "canvas/iris_fingerprint.cc", "Blink sources")
edit("chrome/browser/BUILD.gn", "    \"iris/iris_google_signin_throttle.h\",  # Iris\n",
     "    \"iris/iris_google_signin_throttle.h\",  # Iris\n"
     "    \"iris/iris_fingerprint_host.cc\",  # Iris (B4)\n    \"iris/iris_fingerprint_host.h\",  # Iris (B4)\n",
     "iris/iris_fingerprint_host.cc", "browser sources")

# --- browser binder
b = "chrome/browser/chrome_browser_interface_binders.cc"
edit(b, "  map->Add<blink::mojom::AnchorElementMetricsHost>(\n      &NavigationPredictor::Create);\n",
     "  map->Add<blink::mojom::AnchorElementMetricsHost>(\n      &NavigationPredictor::Create);\n"
     "  // Iris (B4): canvas/audio fingerprint protection.\n"
     "  map->Add<blink::mojom::IrisFingerprintHost>(&iris::BindFingerprintHost);\n",
     "blink::mojom::IrisFingerprintHost", "frame binder")
add_include(b, "#include \"chrome/browser/chrome_browser_interface_binders.h\"\n",
            "#include \"chrome/browser/iris/iris_fingerprint_host.h\"  // Iris (B4)\n"
            "#include \"third_party/blink/public/mojom/iris/iris_fingerprint.mojom.h\"  // Iris (B4)\n")

# --- Blink hooks
INC = "#include \"third_party/blink/renderer/core/html/canvas/iris_fingerprint.h\"  // Iris (B4)\n"
h = "third_party/blink/renderer/core/html/canvas/html_canvas_element.cc"
edit(h, "  scoped_refptr<StaticBitmapImage> image_bitmap = Snapshot(source_buffer);\n  if (image_bitmap) {\n"
        "    std::unique_ptr<ImageDataBuffer> data_buffer =\n",
     "  scoped_refptr<StaticBitmapImage> image_bitmap = Snapshot(source_buffer);\n"
     "  // Iris (B4): canvas fingerprint protection.\n"
     "  image_bitmap = IrisFingerprint::ProtectImage(\n"
     "      GetDocument().GetExecutionContext(), std::move(image_bitmap));\n"
     "  if (image_bitmap) {\n    std::unique_ptr<ImageDataBuffer> data_buffer =\n",
     "ProtectImage(\n      GetDocument().GetExecutionContext(), std::move(image_bitmap));\n  if (image_bitmap) {\n    std::unique_ptr<ImageDataBuffer>",
     "toDataURL")
edit(h, "  scoped_refptr<StaticBitmapImage> image_bitmap = Snapshot(kBackBuffer);\n  if (image_bitmap) {\n",
     "  scoped_refptr<StaticBitmapImage> image_bitmap = Snapshot(kBackBuffer);\n"
     "  // Iris (B4): canvas fingerprint protection.\n"
     "  image_bitmap = IrisFingerprint::ProtectImage(\n"
     "      GetDocument().GetExecutionContext(), std::move(image_bitmap));\n  if (image_bitmap) {\n",
     "Snapshot(kBackBuffer);\n  // Iris (B4)", "toBlob")
add_include(h, "#include \"third_party/blink/renderer/core/html/canvas/html_canvas_element.h\"\n", INC)

o = "third_party/blink/renderer/core/offscreencanvas/offscreen_canvas.cc"
edit(o, "  scoped_refptr<StaticBitmapImage> image_bitmap = context_->GetImage();\n  if (image_bitmap) {\n"
        "    auto* resolver = MakeGarbageCollected<ScriptPromiseResolver<Blob>>(\n",
     "  scoped_refptr<StaticBitmapImage> image_bitmap = context_->GetImage();\n"
     "  // Iris (B4): canvas fingerprint protection.\n"
     "  image_bitmap = IrisFingerprint::ProtectImage(\n"
     "      ExecutionContext::From(script_state), std::move(image_bitmap));\n"
     "  if (image_bitmap) {\n    auto* resolver = MakeGarbageCollected<ScriptPromiseResolver<Blob>>(\n",
     "ExecutionContext::From(script_state), std::move(image_bitmap));", "convertToBlob")
add_include(o, "#include \"third_party/blink/renderer/core/offscreencanvas/offscreen_canvas.h\"\n", INC)

c2 = "third_party/blink/renderer/modules/canvas/canvas2d/base_rendering_context_2d.cc"
for settings_arg, label in (("/*image_data_settings=*/nullptr", "getImageData (4 args)"),
                            ("image_data_settings", "getImageData (settings)")):
    old = ("  return getImageDataInternal(sx, sy, sw, sh, %s,\n"
           "                              exception_state);\n}\n" % settings_arg)
    new = ("  // Iris (B4): canvas fingerprint protection.\n"
           "  return IrisProtectImageData(getImageDataInternal(\n"
           "      sx, sy, sw, sh, %s, exception_state));\n}\n" % settings_arg)
    edit(c2, old, new, "IrisProtectImageData(getImageDataInternal(\n      sx, sy, sw, sh, %s," % settings_arg, label)
edit(c2, "ImageData* BaseRenderingContext2D::getImageData(\n    int sx,\n    int sy,\n    int sw,\n    int sh,\n"
         "    ExceptionState& exception_state) {\n",
     "namespace {\n"
     "// Iris (B4): apply the site's canvas mode to the returned (unpremultiplied RGBA8)\n"
     "// pixels. Other storage formats are left unchanged.\n"
     "ImageData* IrisProtectImageData(ImageData* image_data) {\n"
     "  if (!image_data) {\n    return image_data;\n  }\n"
     "  SkPixmap pixmap = image_data->GetSkPixmap();\n"
     "  if (pixmap.colorType() != kRGBA_8888_SkColorType || !pixmap.writable_addr()) {\n"
     "    return image_data;\n  }\n"
     "  IrisFingerprint::ProtectRGBA8(\n"
     "      CurrentExecutionContext(v8::Isolate::GetCurrent()),\n"
     "      UNSAFE_BUFFERS(base::span<uint8_t>(\n"
     "          static_cast<uint8_t*>(pixmap.writable_addr()),\n"
     "          pixmap.computeByteSize())));\n"
     "  return image_data;\n}\n}  // namespace\n\n"
     "ImageData* BaseRenderingContext2D::getImageData(\n    int sx,\n    int sy,\n    int sw,\n    int sh,\n"
     "    ExceptionState& exception_state) {\n",
     "ImageData* IrisProtectImageData(ImageData* image_data)", "getImageData helper")
add_include(c2, "#include \"third_party/blink/renderer/modules/canvas/canvas2d/base_rendering_context_2d.h\"\n",
            INC + "#include \"base/compiler_specific.h\"  // Iris (B4): UNSAFE_BUFFERS\n"
            "#include \"third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h\"  // Iris (B4)\n")

a = "third_party/blink/renderer/modules/webaudio/audio_buffer.cc"
edit(a, "    return NotShared<DOMFloat32Array>(nullptr);\n  }\n\n  return getChannelData(channel_index);\n}\n",
     "    return NotShared<DOMFloat32Array>(nullptr);\n  }\n\n"
     "  // Iris (B4): audio fingerprint protection (JS-facing overload only; the\n"
     "  // change is idempotent, so repeated calls do not accumulate).\n"
     "  NotShared<DOMFloat32Array> data = getChannelData(channel_index);\n"
     "  if (data) {\n"
     "    IrisFingerprint::ProtectAudio(\n"
     "        CurrentExecutionContext(v8::Isolate::GetCurrent()), data->AsSpan());\n"
     "  }\n  return data;\n}\n",
     "IrisFingerprint::ProtectAudio(\n        CurrentExecutionContext(v8::Isolate::GetCurrent()), data->AsSpan());",
     "getChannelData")
edit(a, "  dst.first(count).copy_from(src.subspan(buffer_offset, count));\n}\n",
     "  dst.first(count).copy_from(src.subspan(buffer_offset, count));\n"
     "  // Iris (B4): same protection as getChannelData (same sample positions).\n"
     "  IrisFingerprint::ProtectAudio(\n"
     "      CurrentExecutionContext(v8::Isolate::GetCurrent()), dst.first(count),\n"
     "      buffer_offset);\n}\n",
     "dst.first(count),\n      buffer_offset);", "copyFromChannel")
add_include(a, "#include \"third_party/blink/renderer/modules/webaudio/audio_buffer.h\"\n",
            INC + "#include \"third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h\"  // Iris (B4)\n")

# --- B4 gaps (2026-09-28): WebGL readPixels (RGBA bytes) + AnalyserNode data
w = "third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc"
edit(w, "    ContextGL()->ReadPixels(x, y, width, height, format, type, data);\n  }\n}\n",
     "    ContextGL()->ReadPixels(x, y, width, height, format, type, data);\n  }\n"
     "  // Iris (B4): WebGL image reads get the same protection as 2D canvas reads\n"
     "  // (RGBA bytes, the format fingerprinting scripts use; WebGL itself is off\n"
     "  // unless the site is allowed). Tightly packed rows assumed.\n"
     "  if (format == GL_RGBA && type == GL_UNSIGNED_BYTE && !buffer &&\n"
     "      width > 0 && height > 0) {\n"
     "    base::CheckedNumeric<size_t> bytes = width;\n"
     "    bytes *= height;\n"
     "    bytes *= 4;\n"
     "    if (bytes.IsValid() &&\n"
     "        bytes.ValueOrDie() <= buffer_size.ValueOrDie()) {\n"
     "      IrisFingerprint::ProtectRGBA8(\n"
     "          Host()->GetTopExecutionContext(),\n"
     "          pixels->ByteSpanMaybeShared().subspan(offset_in_bytes.ValueOrDie(),\n"
     "                                                bytes.ValueOrDie()));\n"
     "    }\n"
     "  }\n}\n",
     "Iris (B4): WebGL image reads", "readPixels")
add_include(w, "#include \"third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.h\"\n", INC)
n = "third_party/blink/renderer/modules/webaudio/analyser_node.cc"
edit(n, "void AnalyserNode::getFloatFrequencyData(NotShared<DOMFloat32Array> array) {\n"
        "  GetAnalyserHandler().GetFloatFrequencyData(array.Get(),\n"
        "                                             context()->currentTime());\n}\n\n"
        "void AnalyserNode::getByteFrequencyData(NotShared<DOMUint8Array> array) {\n"
        "  GetAnalyserHandler().GetByteFrequencyData(array.Get(),\n"
        "                                            context()->currentTime());\n}\n\n"
        "void AnalyserNode::getFloatTimeDomainData(NotShared<DOMFloat32Array> array) {\n"
        "  GetAnalyserHandler().GetFloatTimeDomainData(array.Get());\n}\n\n"
        "void AnalyserNode::getByteTimeDomainData(NotShared<DOMUint8Array> array) {\n"
        "  GetAnalyserHandler().GetByteTimeDomainData(array.Get());\n}\n",
     "// Iris (B4): analyser output gets the same protection as AudioBuffer samples.\n"
     "void AnalyserNode::getFloatFrequencyData(NotShared<DOMFloat32Array> array) {\n"
     "  GetAnalyserHandler().GetFloatFrequencyData(array.Get(),\n"
     "                                             context()->currentTime());\n"
     "  IrisFingerprint::ProtectAudio(context()->GetExecutionContext(),\n"
     "                                array->AsSpan());\n}\n\n"
     "void AnalyserNode::getByteFrequencyData(NotShared<DOMUint8Array> array) {\n"
     "  GetAnalyserHandler().GetByteFrequencyData(array.Get(),\n"
     "                                            context()->currentTime());\n"
     "  IrisFingerprint::ProtectBytes(context()->GetExecutionContext(),\n"
     "                                array->AsSpan());\n}\n\n"
     "void AnalyserNode::getFloatTimeDomainData(NotShared<DOMFloat32Array> array) {\n"
     "  GetAnalyserHandler().GetFloatTimeDomainData(array.Get());\n"
     "  IrisFingerprint::ProtectAudio(context()->GetExecutionContext(),\n"
     "                                array->AsSpan());\n}\n\n"
     "void AnalyserNode::getByteTimeDomainData(NotShared<DOMUint8Array> array) {\n"
     "  GetAnalyserHandler().GetByteTimeDomainData(array.Get());\n"
     "  IrisFingerprint::ProtectBytes(context()->GetExecutionContext(),\n"
     "                                array->AsSpan());\n}\n",
     "Iris (B4): analyser output", "AnalyserNode getters")
add_include(n, "#include \"third_party/blink/renderer/modules/webaudio/analyser_node.h\"\n", INC)

# --- Settings: per-site picker (same pattern as B2's "Browser identity")
hh = "chrome/browser/ui/webui/settings/site_settings_handler.h"
edit(hh, "  void HandleIrisSetUserAgent(const base::ListValue& args);\n",
     "  void HandleIrisSetUserAgent(const base::ListValue& args);\n"
     "  // Iris (B4): per-site canvas/audio reading mode.\n"
     "  void HandleIrisGetFingerprintReads(const base::ListValue& args);\n"
     "  void HandleIrisSetFingerprintReads(const base::ListValue& args);\n",
     "HandleIrisGetFingerprintReads", "handler declarations")
hc = "chrome/browser/ui/webui/settings/site_settings_handler.cc"
edit(hc, "void SiteSettingsHandler::RegisterMessages() {\n  // Iris (B2)\n",
     "void SiteSettingsHandler::HandleIrisGetFingerprintReads(\n    const base::ListValue& args) {\n"
     "  AllowJavascript();\n  CHECK_EQ(2U, args.size());\n"
     "  ResolveJavascriptCallback(\n      args[0], base::Value(iris::GetFingerprintReadsPreset(\n"
     "                   profile_, GURL(args[1].GetString()))));\n}\n\n"
     "void SiteSettingsHandler::HandleIrisSetFingerprintReads(\n    const base::ListValue& args) {\n"
     "  CHECK_EQ(2U, args.size());\n"
     "  iris::SetFingerprintReadsPreset(profile_, GURL(args[0].GetString()),\n"
     "                                  args[1].GetString());\n}\n\n"
     "void SiteSettingsHandler::RegisterMessages() {\n"
     "  // Iris (B4)\n"
     "  web_ui()->RegisterMessageCallback(\n      \"irisGetFingerprintReads\",\n"
     "      base::BindRepeating(&SiteSettingsHandler::HandleIrisGetFingerprintReads,\n"
     "                          base::Unretained(this)));\n"
     "  web_ui()->RegisterMessageCallback(\n      \"irisSetFingerprintReads\",\n"
     "      base::BindRepeating(&SiteSettingsHandler::HandleIrisSetFingerprintReads,\n"
     "                          base::Unretained(this)));\n"
     "  // Iris (B2)\n",
     "\"irisGetFingerprintReads\"", "handler + messages")
add_include(hc, "#include \"chrome/browser/iris/iris_user_agent.h\"  // Iris (B2)\n",
            "#include \"chrome/browser/iris/iris_fingerprint_host.h\"  // Iris (B4)\n")
edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     "      {\"irisUserAgent\", IDS_SETTINGS_IRIS_USER_AGENT},  // Iris (B2)\n",
     "      {\"irisUserAgent\", IDS_SETTINGS_IRIS_USER_AGENT},  // Iris (B2)\n"
     "      {\"irisFingerprintReads\", IDS_SETTINGS_IRIS_FINGERPRINT_READS},  // Iris (B4)\n"
     "      {\"irisFingerprintReadsProtected\",\n       IDS_SETTINGS_IRIS_FINGERPRINT_READS_PROTECTED},\n"
     "      {\"irisFingerprintReadsBlank\", IDS_SETTINGS_IRIS_FINGERPRINT_READS_BLANK},\n"
     "      {\"irisFingerprintReadsReal\", IDS_SETTINGS_IRIS_FINGERPRINT_READS_REAL},\n",
     "\"irisFingerprintReads\"", "strings registered")
d = "chrome/browser/resources/settings/site_settings/site_details.html"
edit(d, "      <!-- Iris (B2): per-site browser identity (apply-user-agent.sh) -->\n",
     "      <!-- Iris (B4): per-site canvas/audio reading (apply-fingerprint.sh) -->\n"
     "      <div class=\"cr-row\" id=\"irisFingerprintReadsRow\">\n"
     "        <div class=\"flex\">$i18n{irisFingerprintReads}</div>\n"
     "        <select class=\"md-select\" id=\"irisFingerprintReadsSelect\"\n"
     "            aria-label=\"$i18n{irisFingerprintReads}\"\n"
     "            on-change=\"onIrisFingerprintReadsChange_\">\n"
     "          <option value=\"protected\" selected=\"[[isIrisValue_(irisFingerprintReads_, 'protected')]]\">$i18n{irisFingerprintReadsProtected}</option>\n"
     "          <option value=\"blank\" selected=\"[[isIrisValue_(irisFingerprintReads_, 'blank')]]\">$i18n{irisFingerprintReadsBlank}</option>\n"
     "          <option value=\"real\" selected=\"[[isIrisValue_(irisFingerprintReads_, 'real')]]\">$i18n{irisFingerprintReadsReal}</option>\n"
     "        </select>\n"
     "      </div>\n"
     "      <!-- Iris (B2): per-site browser identity (apply-user-agent.sh) -->\n",
     "irisFingerprintReadsSelect", "picker")
ts = "chrome/browser/resources/settings/site_settings/site_details.ts"
edit(ts, "      irisUserAgent_: {type: String, value: ''},\n",
     "      irisUserAgent_: {type: String, value: ''},\n"
     "      // Iris (B4): 'protected' | 'blank' | 'real'.\n"
     "      irisFingerprintReads_: {type: String, value: 'protected'},\n",
     "irisFingerprintReads_: {type: String", "property")
edit(ts, "  declare private irisUserAgent_: string;  // Iris (B2)\n",
     "  declare private irisUserAgent_: string;  // Iris (B2)\n"
     "  declare private irisFingerprintReads_: string;  // Iris (B4)\n",
     "declare private irisFingerprintReads_", "property type")
edit(ts, "        // Iris (B2): load this site's browser identity.\n",
     "        // Iris (B4): load this site's canvas/audio reading mode.\n"
     "        sendWithPromise('irisGetFingerprintReads', this.origin_)\n"
     "            .then((mode) => {\n"
     "              this.irisFingerprintReads_ = mode as string;\n"
     "            });\n"
     "        // Iris (B2): load this site's browser identity.\n",
     "sendWithPromise('irisGetFingerprintReads'", "load on open")
edit(ts, "  private onIrisUserAgentChange_(e: Event) {\n",
     "  private isIrisValue_(current: string, value: string): boolean {\n"
     "    return current === value;\n  }\n\n"
     "  private onIrisFingerprintReadsChange_(e: Event) {\n"
     "    const mode = (e.target as HTMLSelectElement).value;\n"
     "    this.irisFingerprintReads_ = mode;\n"
     "    chrome.send('irisSetFingerprintReads', [this.origin_, mode]);\n  }\n\n"
     "  private onIrisUserAgentChange_(e: Event) {\n",
     "onIrisFingerprintReadsChange_(e: Event)", "change handler")
PY
echo "=== canvas/audio fingerprint protection complete ==="
