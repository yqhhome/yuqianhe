package com.example.singbox_client

import android.app.Activity
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.net.TrafficStats
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat
import io.nekohasekai.libbox.Libbox
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.InetAddress
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ServerSocket
import java.net.URL
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "yuqianhe/singbox_android"
        private const val SINGBOX_VERSION = "1.13.4"
        private const val REQUEST_VPN_PERMISSION = 7001
        private const val LIBBOX_MIXED_PORT = 2080
        private var singProcess: Process? = null
        private val processLock = Any()
    }

    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingVpnConfigPath: String? = null
    private val connectivity by lazy {
        getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank()) {
                            result.error("invalid_args", "missing config", null)
                            return@setMethodCallHandler
                        }
                        startSingbox(config, result)
                    }
                    "measureLatency" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank()) {
                            result.error("invalid_args", "missing config", null)
                            return@setMethodCallHandler
                        }
                        measureLatency(config, result)
                    }
                    "diagnose" -> {
                        diagnose(result)
                    }
                    "setSystemProxy" -> {
                        val enable = call.argument<Boolean>("enable") == true
                        val host = call.argument<String>("host") ?: "127.0.0.1"
                        val port = call.argument<Int>("port") ?: 2080
                        setSystemProxy(enable, host, port, result)
                    }
                    "readTrafficStats" -> {
                        result.success(
                            mapOf(
                                "rx" to TrafficStats.getTotalRxBytes(),
                                "tx" to TrafficStats.getTotalTxBytes(),
                            )
                        )
                    }
                    "stop" -> {
                        stopSingbox()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN_PERMISSION) {
            return
        }
        val callback = pendingVpnResult
        pendingVpnResult = null
        val configPath = pendingVpnConfigPath
        pendingVpnConfigPath = null
        if (callback == null) {
            return
        }
        if (resultCode == Activity.RESULT_OK) {
            if (!configPath.isNullOrBlank()) {
                startLibboxVpn(configPath, callback)
            } else {
                callback.error("vpn_start_failed", "missing libbox config after VPN permission grant", null)
            }
        } else {
            callback.error("vpn_permission_denied", "Android VPN permission denied", null)
        }
    }

    private fun startSingbox(configJson: String, result: MethodChannel.Result) {
        Thread {
            try {
                synchronized(processLock) {
                    stopSingboxLocked()
                }
                stopLibboxVpn()
                val baseConfig = overrideMixedInboundPort(configJson, LIBBOX_MIXED_PORT)
                val effectiveConfig = ensureTunInbound(baseConfig)
                val useTun = hasTunInbound(effectiveConfig)
                val cfg = File(cacheDir, "singbox_android_run.json")
                cfg.writeText(effectiveConfig)
                val prepareIntent = if (useTun) VpnService.prepare(this) else null
                if (useTun && prepareIntent != null) {
                    pendingVpnResult = result
                    pendingVpnConfigPath = cfg.absolutePath
                    runOnUiThread {
                        startActivityForResult(prepareIntent, REQUEST_VPN_PERMISSION)
                    }
                    return@Thread
                }
                startLibboxVpn(cfg.absolutePath, result)
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("start_exception", e.message ?: e.toString(), null)
                }
            }
        }.start()
    }

    private fun measureLatency(configJson: String, result: MethodChannel.Result) {
        Thread {
            var proc: Process? = null
            try {
                val bin = ensureSingboxBinary()
                val mixedPort = pickFreePort()
                val cfg = File(
                    cacheDir,
                    "singbox_android_probe_${System.currentTimeMillis()}.json"
                )
                val effectiveConfig = overrideMixedInboundPort(configJson, mixedPort)
                cfg.writeText(effectiveConfig)
                proc = ProcessBuilder(bin.absolutePath, "run", "-c", cfg.absolutePath)
                    .redirectErrorStream(true)
                    .start()
                Thread.sleep(320)
                if (!proc.isAlive) {
                    runOnUiThread { result.success(null) }
                    return@Thread
                }
                val latency = probeLatencyViaLocalProxy(mixedPort)
                runOnUiThread { result.success(latency) }
            } catch (_: Exception) {
                runOnUiThread { result.success(null) }
            } finally {
                try {
                    proc?.destroy()
                    proc?.waitFor(2, TimeUnit.SECONDS)
                    if (proc?.isAlive == true) {
                        proc?.destroyForcibly()
                    }
                } catch (_: Exception) {}
            }
        }.start()
    }

    private fun diagnose(result: MethodChannel.Result) {
        Thread {
            val data = linkedMapOf<String, Any?>()
            try {
                val pkg = packageManager.getPackageInfo(packageName, 0)
                data["buildVersion"] = pkg.versionName
                @Suppress("DEPRECATION")
                data["buildCode"] = pkg.versionCode
            } catch (_: Exception) {}
            data["abi"] = android.os.Build.SUPPORTED_ABIS.joinToString(",")
            data["archMapped"] = mapArch()
            data["libboxVersion"] = runCatching { Libbox.version() }.getOrNull()
            data["libboxRunning"] = LocalProxyVpnService.isRunning()
            data["libboxError"] = LocalProxyVpnService.getLastError()
            data["libboxConfigPath"] = LocalProxyVpnService.getCurrentConfigPath()
            data["tunDnsServer"] = LocalProxyVpnService.getLastTunDnsServer()
            data["upstreamInterface"] = LocalProxyVpnService.getLastUpstreamInterface()
            data["nativeLibDir"] = applicationInfo.nativeLibraryDir
            data["vpnPrepared"] = VpnService.prepare(this) == null
            val assetNames = listBundledArchives()
            data["assetList"] = assetNames.joinToString(",")
            val assetGz = "sing-box-$SINGBOX_VERSION-android-${mapArch()}.tar.gz"
            val assetTar = "sing-box-$SINGBOX_VERSION-android-${mapArch()}.tar"
            data["assetTarGzExists"] = assetNames.contains(assetGz)
            data["assetTarExists"] = assetNames.contains(assetTar)
            val bin = File(applicationInfo.nativeLibraryDir, "libsing-box.so")
            data["binExists"] = bin.exists()
            data["binCanExecute"] = bin.canExecute()
            data["binSize"] = if (bin.exists()) bin.length() else 0L
            try {
                val ensured = ensureSingboxBinary()
                data["ensureOk"] = true
                data["ensuredBinSize"] = ensured.length()
            } catch (e: Exception) {
                data["ensureOk"] = false
                data["ensureError"] = "${e.javaClass.simpleName}: ${e.message ?: ""}"
            }
            val activeNetwork = runCatching { connectivity.activeNetwork }.getOrNull()
            val linkProperties = runCatching { connectivity.getLinkProperties(activeNetwork) }.getOrNull()
            data["activeNetworkInterface"] = linkProperties?.interfaceName
            data["activeDnsServers"] = linkProperties?.dnsServers
                ?.mapNotNull { it.hostAddress ?: it.hostName }
                ?.joinToString(",")
                ?: ""
            val configPath = LocalProxyVpnService.getCurrentConfigPath()
            val configText = configPath?.let { path ->
                runCatching { File(path).readText() }.getOrNull()
            }
            if (!configText.isNullOrBlank()) {
                runCatching {
                    val root = JSONObject(configText)
                    val dns = root.optJSONObject("dns")
                    val route = root.optJSONObject("route")
                    data["configHasTun"] = hasTunInbound(configText)
                    data["dnsFinal"] = dns?.optString("final") ?: ""
                    data["routeDefaultResolver"] = route?.optString("default_domain_resolver") ?: ""
                    data["quicFallbackEnabled"] = hasUdp443Block(route?.optJSONArray("rules"))
                }
            }
            data["resolveGoogle"] = resolveDomain("www.google.com")
            data["resolveYouTube"] = resolveDomain("www.youtube.com")
            data["resolveYouTubeApi"] = resolveDomain("youtubei.googleapis.com")
            data["proxyGoogle204"] = probeUrlViaLocalProxy("https://www.google.com/generate_204")
            data["proxyGoogleHome"] = probeUrlViaLocalProxy("https://www.google.com/")
            data["proxyYouTubeHome"] = probeUrlViaLocalProxy("https://www.youtube.com/")
            data["proxyYouTubeApi"] = probeUrlViaLocalProxy("https://youtubei.googleapis.com/")
            data["directGoogleHome"] = probeUrlDirect("https://www.google.com/")
            data["directFacebookHome"] = probeUrlDirect("https://www.facebook.com/")
            runOnUiThread { result.success(data) }
        }.start()
    }

    private fun hasUdp443Block(rules: JSONArray?): Boolean {
        if (rules == null) {
            return false
        }
        for (i in 0 until rules.length()) {
            val item = rules.optJSONObject(i) ?: continue
            if (item.optString("network") == "udp" &&
                item.opt("port")?.toString() == "443" &&
                item.optString("outbound") == "block"
            ) {
                return true
            }
        }
        return false
    }

    private fun resolveDomain(domain: String): String {
        return try {
            InetAddress.getAllByName(domain)
                .mapNotNull { it.hostAddress }
                .distinct()
                .joinToString(",")
                .ifBlank { "empty" }
        } catch (e: Exception) {
            "error:${e.javaClass.simpleName}:${e.message ?: ""}"
        }
    }

    private fun probeUrlViaLocalProxy(target: String): String {
        return try {
            val proxy = Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", LIBBOX_MIXED_PORT))
            val conn = URL(target).openConnection(proxy) as HttpURLConnection
            conn.connectTimeout = 4000
            conn.readTimeout = 5000
            conn.instanceFollowRedirects = true
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "yuqianhe-android-runtime-diagnose")
            val code = conn.responseCode
            val finalUrl = conn.url?.toString() ?: target
            conn.inputStream?.close()
            "code=$code final=$finalUrl"
        } catch (e: Exception) {
            "error:${e.javaClass.simpleName}:${e.message ?: ""}"
        }
    }

    private fun probeUrlDirect(target: String): String {
        return try {
            val conn = URL(target).openConnection() as HttpURLConnection
            conn.connectTimeout = 4000
            conn.readTimeout = 5000
            conn.instanceFollowRedirects = true
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "yuqianhe-android-runtime-diagnose-direct")
            val code = conn.responseCode
            val finalUrl = conn.url?.toString() ?: target
            conn.inputStream?.close()
            "code=$code final=$finalUrl"
        } catch (e: Exception) {
            "error:${e.javaClass.simpleName}:${e.message ?: ""}"
        }
    }

    private fun setSystemProxy(
        enable: Boolean,
        host: String,
        port: Int,
        result: MethodChannel.Result,
    ) {
        result.success(true)
    }

    private fun stopLibboxVpn() {
        try {
            val intent = Intent(this, LocalProxyVpnService::class.java).apply {
                action = LocalProxyVpnService.ACTION_STOP
            }
            startService(intent)
        } catch (_: Exception) {
        }
    }

    private fun stopSingbox() {
        synchronized(processLock) {
            stopSingboxLocked()
        }
        stopLibboxVpn()
    }

    private fun stopSingboxLocked() {
        val p = singProcess
        if (p != null) {
            try {
                p.destroy()
                p.waitFor(3, TimeUnit.SECONDS)
                if (p.isAlive) {
                    p.destroyForcibly()
                }
            } catch (_: Exception) {}
        }
        singProcess = null
    }

    private fun ensureSingboxBinary(): File {
        val candidates = listOf(
            File(applicationInfo.nativeLibraryDir, "libsing-box.so"),
            File(applicationInfo.nativeLibraryDir, "libsing_box.so"),
        )
        for (target in candidates) {
            if (target.exists() && target.length() > 512 * 1024) {
                return target
            }
        }
        throw IllegalStateException(
            "native sing-box missing in ${applicationInfo.nativeLibraryDir}"
        )
    }

    private fun mapArch(): String {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        return when {
            abi.contains("arm64") -> "arm64"
            abi.contains("armeabi") || abi.contains("armv7") -> "arm"
            abi.contains("x86_64") -> "amd64"
            abi.contains("x86") -> "386"
            else -> "arm64"
        }
    }

    private fun listBundledArchives(): List<String> {
        return try {
            assets.list("singbox")?.toList()?.sorted() ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun pickFreePort(): Int {
        return try {
            ServerSocket(0).use { it.localPort }
        } catch (_: Exception) {
            2080
        }
    }

    private fun overrideMixedInboundPort(configJson: String, port: Int): String {
        return try {
            val root = JSONObject(configJson)
            val inbounds = root.optJSONArray("inbounds") ?: JSONArray()
            for (i in 0 until inbounds.length()) {
                val item = inbounds.optJSONObject(i) ?: continue
                if (item.optString("type") == "mixed") {
                    item.put("listen", "127.0.0.1")
                    item.put("listen_port", port)
                }
            }
            root.toString(2)
        } catch (_: Exception) {
            configJson
        }
    }

    private fun ensureTunInbound(configJson: String): String {
        return try {
            val root = JSONObject(configJson)
            val inbounds = root.optJSONArray("inbounds") ?: JSONArray()
            var hasTun = false
            for (i in 0 until inbounds.length()) {
                val item = inbounds.optJSONObject(i) ?: continue
                if (item.optString("type") == "tun") {
                    hasTun = true
                    item.put("tag", "tun-in")
                    val address = JSONArray()
                    val currentAddress = item.optJSONArray("address")
                    if (currentAddress != null && currentAddress.length() > 0) {
                        for (j in 0 until currentAddress.length()) {
                            address.put(currentAddress.opt(j))
                        }
                    } else {
                        val legacyInet4 = item.opt("inet4_address")
                        when (legacyInet4) {
                            is JSONArray -> {
                                for (j in 0 until legacyInet4.length()) {
                                    address.put(legacyInet4.opt(j))
                                }
                            }
                            is String -> {
                                if (legacyInet4.isNotBlank()) {
                                    address.put(legacyInet4)
                                }
                            }
                        }
                    }
                    if (address.length() == 0) {
                        address.put("172.19.0.1/30")
                    }
                    item.put("address", address)
                    item.remove("inet4_address")
                    item.remove("inet6_address")
                    item.remove("inet4_route_address")
                    item.remove("inet6_route_address")
                    item.remove("inet4_route_exclude_address")
                    item.remove("inet6_route_exclude_address")
                    item.put("auto_route", true)
                    item.put("strict_route", true)
                    item.put("stack", item.optString("stack", "system"))
                }
            }
            if (!hasTun) {
                return configJson
            }
            val route = root.optJSONObject("route") ?: JSONObject()
            route.put("auto_detect_interface", true)
            route.put("override_android_vpn", true)
            if (!route.has("final")) {
                route.put("final", "proxy")
            }
            root.put("route", route)
            root.toString(2)
        } catch (_: Exception) {
            configJson
        }
    }

    private fun hasTunInbound(configJson: String): Boolean {
        return try {
            val root = JSONObject(configJson)
            val inbounds = root.optJSONArray("inbounds") ?: return false
            for (i in 0 until inbounds.length()) {
                val item = inbounds.optJSONObject(i) ?: continue
                if (item.optString("type") == "tun") {
                    return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun startLibboxVpn(configPath: String, result: MethodChannel.Result) {
        Thread {
            try {
                LocalProxyVpnService.clearLastError()
                val intent = Intent(this, LocalProxyVpnService::class.java).apply {
                    action = LocalProxyVpnService.ACTION_START
                    putExtra(LocalProxyVpnService.EXTRA_CONFIG_PATH, configPath)
                }
                ContextCompat.startForegroundService(this, intent)
                repeat(75) {
                    val err = LocalProxyVpnService.getLastError()
                    if (!err.isNullOrBlank()) {
                        runOnUiThread {
                            result.error("start_failed", err, null)
                        }
                        return@Thread
                    }
                    if (LocalProxyVpnService.isRunning()) {
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "mixedPort" to LIBBOX_MIXED_PORT,
                                )
                            )
                        }
                        return@Thread
                    }
                    Thread.sleep(200)
                }
                val err = LocalProxyVpnService.getLastError() ?: "libbox vpn start timeout"
                runOnUiThread {
                    result.error("start_timeout", err, null)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("start_exception", e.message ?: e.toString(), null)
                }
            }
        }.start()
    }

    private fun probeLatencyViaLocalProxy(port: Int): Int? {
        val targets = listOf(
            "https://www.google.com/generate_204",
            "https://connectivitycheck.gstatic.com/generate_204",
            "https://www.baidu.com/",
        )
        for (target in targets) {
            try {
                val started = System.nanoTime()
                val proxy = Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", port))
                val conn = URL(target).openConnection(proxy) as HttpURLConnection
                conn.connectTimeout = 2500
                conn.readTimeout = 3500
                conn.instanceFollowRedirects = true
                conn.requestMethod = "GET"
                conn.setRequestProperty("User-Agent", "yuqianhe-android-singbox-client")
                val code = conn.responseCode
                val ok = if (target.contains("generate_204")) {
                    code == 204
                } else {
                    code in 200..399
                }
                if (ok) {
                    val elapsedMs = ((System.nanoTime() - started) / 1_000_000L).toInt()
                    return if (elapsedMs > 0) elapsedMs else 1
                }
            } catch (_: Exception) {
                // try next target
            }
        }
        return null
    }

}
