#!/usr/bin/env bash
# Iris — "Strict post-quantum encryption" setting, default OFF (jegly 2026-10-03; verified against the
# 156.0.8073.0 sources + BoringSSL 5fbad228 / quiche 535a2730 from DEPS).
# Before: the CNSA preset (apply-tls-hardening.sh step 3) OFFERS ML-KEM-1024 first but sends key shares only for
# X25519MLKEM768 + X25519 (services/network/ssl_config_type_converter.cc), so servers that support both pick
# X25519MLKEM768; ML-KEM-1024 is used only when a server asks for it (HelloRetryRequest). TLS 1.3 offers
# AES-256-GCM first, then AES-128-GCM and ChaCha20-Poly1305.
# After, with the setting ON (browser-wide Local State pref "iris.tls.strict_pq"):
#  - key shares ML-KEM-1024 + X25519MLKEM768 + X25519 (group order unchanged: MLKEM1024, X25519MLKEM768, P-384,
#    P-256, X25519). Sites without ML-KEM-1024 still work (no extra round trip). ClientHello grows ~1.6 KB.
#  - TLS 1.3 offers ONLY TLS_AES_256_GCM_SHA384 (SSL_set1_tls13_ciphers; QUIC: SSL_CTX_set1_tls13_ciphers on the
#    QUIC client SSL_CTX instead of the cnsa_202407 compliance policy, which would replace the list). A server
#    without AES-256-GCM fails to connect (TLS 1.3 servers must support AES-128-GCM, AES-256 is only "should").
#    TLS 1.2 is already off (apply-tls-hardening.sh step 1), so there is no TLS 1.2 cipher list to restrict.
# Plumbing: pref -> SSLConfigServiceManager (mojom SSLConfig.iris_strict_pq_tls) -> network service converter ->
# net::SSLContextConfig (groups + tls13_aes_256_only) -> SSLClientSocketImpl (TCP) / QuicSessionPool (QUIC).
# TCP connections pick up a change at once (SSLClientContext flushes its session cache); QUIC crypto configs are
# cached per network-anonymization key, so QUIC needs a restart -> the label says "Restart Iris".
# UI: desktop Settings -> Privacy and security -> Security (both security_page.html and security_page_v2.html, only
# one is shown); Android Settings -> Privacy and security -> Iris (LocalStatePrefs). English-only labels on purpose
# (a new grit string would rebuild thousands of files). TODO (release): localize.
# Rebuild cost: ssl_config.mojom + net/ssl/ssl_config_service.h are widely included (large incremental rebuild).
# Needs (anchors): apply-tls-hardening.sh, apply-android-iris-privacy-settings.sh. Run after them.
# STATUS 2026-10-03: copy-tested only, NOT compile-proven. Compile-prove the touched objects before the next build.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
PREF = "iris.tls.strict_pq"
LABEL = "Strict post-quantum encryption"
SUB = ("Offers ML-KEM-1024 key exchange first and uses only AES-256 encryption. Some websites may not load. "
       "Restart Iris to apply it to all connections.")

# 1) mojom: one new field, default false.
edit("services/network/public/mojom/ssl_config.mojom",
     "  bool tls13_cipher_prefer_aes_256 = false;\n",
     "  bool tls13_cipher_prefer_aes_256 = false;\n"
     "\n"
     "  // Iris: \"Strict post-quantum encryption\" setting. Sends an ML-KEM-1024\n"
     "  // key share (with the CNSA 2.0 group order) and offers only\n"
     "  // TLS_AES_256_GCM_SHA384 for TLS 1.3.\n"
     "  bool iris_strict_pq_tls = false;\n",
     "iris_strict_pq_tls", "mojom SSLConfig.iris_strict_pq_tls")

# 2) net::SSLContextConfig: AES-256-only flag.
edit("net/ssl/ssl_config_service.h",
     "  bool tls13_cipher_prefer_aes_256 = false;\n",
     "  bool tls13_cipher_prefer_aes_256 = false;\n"
     "\n"
     "  // Iris: offer only TLS_AES_256_GCM_SHA384 for TLS 1.3 (TCP and QUIC).\n"
     "  bool tls13_aes_256_only = false;\n",
     "tls13_aes_256_only", "SSLContextConfig.tls13_aes_256_only")

# 3) network service: mojom -> net config.
edit("services/network/ssl_config_type_converter.cc",
     "      break;\n"
     "  }\n"
     "\n"
     "  if (mojo_config->time_bound_trust_anchor_ids) {\n",
     "      break;\n"
     "  }\n"
     "\n"
     "  // Iris: \"Strict post-quantum encryption\". Same groups as kCnsa2, plus an\n"
     "  // ML-KEM-1024 key share; TLS 1.3 offers only AES-256-GCM.\n"
     "  if (mojo_config->iris_strict_pq_tls) {\n"
     "    net_config.supported_named_groups = {\n"
     "        {.group_id = SSL_GROUP_MLKEM1024, .send_key_share = true},\n"
     "        {.group_id = SSL_GROUP_X25519_MLKEM768, .send_key_share = true},\n"
     "        {.group_id = SSL_GROUP_SECP384R1, .send_key_share = false},\n"
     "        {.group_id = SSL_GROUP_SECP256R1, .send_key_share = false},\n"
     "        {.group_id = SSL_GROUP_X25519, .send_key_share = true},\n"
     "    };\n"
     "    net_config.tls13_cipher_prefer_aes_256 = true;\n"
     "    net_config.tls13_aes_256_only = true;\n"
     "  }\n"
     "\n"
     "  if (mojo_config->time_bound_trust_anchor_ids) {\n",
     "iris_strict_pq_tls", "converter: groups + AES-256 only")

# 4) TCP TLS: restrict the TLS 1.3 cipher list after the compliance policy (which sets the list too).
edit("net/socket/ssl_client_socket_impl.cc",
     "  if (context_->config().tls13_cipher_prefer_aes_256 &&\n"
     "      !SSL_set_compliance_policy(ssl_.get(),\n"
     "                                 ssl_compliance_policy_cnsa_202407)) {\n"
     "    return ERR_UNEXPECTED;\n"
     "  }\n",
     "  if (context_->config().tls13_cipher_prefer_aes_256 &&\n"
     "      !SSL_set_compliance_policy(ssl_.get(),\n"
     "                                 ssl_compliance_policy_cnsa_202407)) {\n"
     "    return ERR_UNEXPECTED;\n"
     "  }\n"
     "\n"
     "  // Iris: \"Strict post-quantum encryption\": offer only AES-256-GCM. Must\n"
     "  // come after the compliance policy, which replaces the TLS 1.3 list.\n"
     "  if (context_->config().tls13_aes_256_only) {\n"
     "    static constexpr uint16_t kIrisTls13Cipher = SSL_CIPHER_AES_256_GCM_SHA384;\n"
     "    if (!SSL_set1_tls13_ciphers(ssl_.get(), &kIrisTls13Cipher,\n"
     "                                /*flags=*/nullptr, /*num_cipher_ids=*/1)) {\n"
     "      return ERR_UNEXPECTED;\n"
     "    }\n"
     "  }\n",
     "tls13_aes_256_only", "TCP: TLS 1.3 AES-256-GCM only")

# 5) QUIC: same restriction on the QUIC client SSL_CTX (key shares already follow GetSupportedGroups()).
edit("net/quic/quic_session_pool.cc",
     "  if (quic_session_pool_->ssl_config_service_->GetSSLContextConfig()\n"
     "          .tls13_cipher_prefer_aes_256) {\n"
     "    config_.set_ssl_compliance_policy(ssl_compliance_policy_cnsa_202407);\n"
     "  }\n",
     "  // Iris: \"Strict post-quantum encryption\": offer only AES-256-GCM. Set on\n"
     "  // the SSL_CTX (copied into each connection); the compliance policy is not\n"
     "  // set then, because it would replace this list per connection.\n"
     "  if (quic_session_pool_->ssl_config_service_->GetSSLContextConfig()\n"
     "          .tls13_aes_256_only) {\n"
     "    static constexpr uint16_t kIrisTls13Cipher = SSL_CIPHER_AES_256_GCM_SHA384;\n"
     "    CHECK(SSL_CTX_set1_tls13_ciphers(config_.ssl_ctx(), &kIrisTls13Cipher,\n"
     "                                     /*flags=*/nullptr,\n"
     "                                     /*num_cipher_ids=*/1));\n"
     "  } else if (quic_session_pool_->ssl_config_service_->GetSSLContextConfig()\n"
     "                 .tls13_cipher_prefer_aes_256) {\n"
     "    config_.set_ssl_compliance_policy(ssl_compliance_policy_cnsa_202407);\n"
     "  }\n",
     "tls13_aes_256_only", "QUIC: TLS 1.3 AES-256-GCM only")

# 6) Browser side: Local State pref -> mojom field; changes are pushed like the other TLS prefs.
p = "chrome/browser/ssl/ssl_config_service_manager.cc"
edit(p,
     "const char kPrefStringValueCnsa[] = \"cnsa\";\n",
     "const char kPrefStringValueCnsa[] = \"cnsa\";\n"
     "\n"
     "// Iris: Local State pref behind Settings -> \"Strict post-quantum encryption\".\n"
     "const char kIrisStrictPqTlsPref[] = \"%s\";\n" % PREF,
     "kIrisStrictPqTlsPref[]", "pref name constant")
edit(p,
     "  local_state_change_registrar_.Add(prefs::kCipherSuiteBlacklist,\n"
     "                                    local_state_callback);\n",
     "  local_state_change_registrar_.Add(prefs::kCipherSuiteBlacklist,\n"
     "                                    local_state_callback);\n"
     "  local_state_change_registrar_.Add(kIrisStrictPqTlsPref,\n"
     "                                    local_state_callback);\n",
     "local_state_change_registrar_.Add(kIrisStrictPqTlsPref", "observe pref")
edit(p,
     "  registry->RegisterStringPref(prefs::kPreferSlowCiphers, std::string());\n"
     "}\n",
     "  registry->RegisterStringPref(prefs::kPreferSlowCiphers, std::string());\n"
     "  // Iris: off by default.\n"
     "  registry->RegisterBooleanPref(kIrisStrictPqTlsPref, false);\n"
     "}\n",
     "RegisterBooleanPref(kIrisStrictPqTlsPref", "register pref (Local State, default false)")
edit(p,
     "  ConfigureSSLComplianceSettings(key_exchange_compliance_,\n"
     "                                 tls13_cipher_compliance_, config.get());\n",
     "  ConfigureSSLComplianceSettings(key_exchange_compliance_,\n"
     "                                 tls13_cipher_compliance_, config.get());\n"
     "\n"
     "  config->iris_strict_pq_tls =\n"
     "      local_state_change_registrar_.prefs()->GetBoolean(kIrisStrictPqTlsPref);\n",
     "config->iris_strict_pq_tls", "pref -> SSLConfig")

# 7) Desktop Settings: allowlist (FindServiceForPref falls back to Local State) + toggles.
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[::prefs::kHardwareAccelerationModeEnabled] =\n"
     "      settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[::prefs::kHardwareAccelerationModeEnabled] =\n"
     "      settings_api::PrefType::kBoolean;\n"
     "  // Iris: Settings -> Security -> \"Strict post-quantum encryption\".\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % PREF,
     PREF, "settings may read/write %s" % PREF)

TOGGLE = ("    <!-- Iris: strict post-quantum encryption (apply-strict-pq-tls.sh; English-only label, TODO localize) -->\n"
          "    <settings-toggle-button id=\"irisStrictPqTls\" class=\"hr\"\n"
          "        pref=\"{{prefs.iris.tls.strict_pq}}\"\n"
          "        label=\"%s\"\n"
          "        sub-label=\"%s\">\n"
          "    </settings-toggle-button>\n" % (LABEL, SUB))
SEC = "chrome/browser/resources/settings/privacy_page/security/"
edit(SEC + "security_page.html",
     "        </settings-secure-dns>\n"
     "      </template>\n"
     "    </template>\n"
     "<if expr=\"is_chromeos\">\n",
     "        </settings-secure-dns>\n"
     "      </template>\n"
     "    </template>\n" + TOGGLE +
     "<if expr=\"is_chromeos\">\n",
     "irisStrictPqTls", "Security page toggle")
edit(SEC + "security_page_v2.html",
     "      </settings-secure-dns>\n"
     "    </template>\n"
     "    <template is=\"dom-if\" if=\"[[enableSecurityKeysSubpage_]]\">\n",
     "      </settings-secure-dns>\n"
     "    </template>\n" + TOGGLE +
     "    <template is=\"dom-if\" if=\"[[enableSecurityKeysSubpage_]]\">\n",
     "irisStrictPqTls", "Security page (v2) toggle")

# 8) Android Settings -> Privacy and security -> Iris: switch on the same Local State pref.
edit("chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java",
     "        irisCategory.addPreference(irisGoogleSignin);\n",
     "        irisCategory.addPreference(irisGoogleSignin);\n"
     "        // Iris: \"Strict post-quantum encryption\" (browser-wide Local State pref).\n"
     "        ChromeSwitchPreference irisStrictPqTls =\n"
     "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
     "        irisStrictPqTls.setKey(\"iris_strict_pq_tls\");\n"
     "        irisStrictPqTls.setPersistent(false);\n"
     "        irisStrictPqTls.setTitle(\"%s\");\n"
     "        irisStrictPqTls.setSummary(\n"
     "                \"%s\");\n"
     "        org.chromium.components.prefs.PrefService irisLocalState =\n"
     "                org.chromium.chrome.browser.prefs.LocalStatePrefs.get();\n"
     "        irisStrictPqTls.setEnabled(irisLocalState != null);\n"
     "        irisStrictPqTls.setChecked(\n"
     "                irisLocalState != null && irisLocalState.getBoolean(\"%s\"));\n"
     "        irisStrictPqTls.setOnPreferenceChangeListener(\n"
     "                (preference, newValue) -> {\n"
     "                    org.chromium.components.prefs.PrefService localState =\n"
     "                            org.chromium.chrome.browser.prefs.LocalStatePrefs.get();\n"
     "                    if (localState == null) return false;\n"
     "                    localState.setBoolean(\"%s\", (Boolean) newValue);\n"
     "                    return true;\n"
     "                });\n"
     "        irisCategory.addPreference(irisStrictPqTls);\n" % (LABEL, SUB, PREF, PREF),
     "irisStrictPqTls", "Android Iris section switch")
PY
echo "=== strict post-quantum TLS setting complete ==="
