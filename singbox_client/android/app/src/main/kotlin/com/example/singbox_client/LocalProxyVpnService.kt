package com.example.singbox_client

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.Network
import android.net.NetworkCapabilities
import android.net.ProxyInfo
import android.net.VpnService
import android.os.CancellationSignal
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborEntry
import io.nekohasekai.libbox.NeighborEntryIterator
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification as LibboxNotification
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.io.File
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.net.UnknownHostException
import java.security.KeyStore
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.runBlocking
import kotlin.concurrent.thread
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

class LocalProxyVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    companion object {
        const val ACTION_START = "com.example.singbox_client.action.START_PROXY_VPN"
        const val ACTION_STOP = "com.example.singbox_client.action.STOP_PROXY_VPN"
        const val EXTRA_CONFIG_PATH = "config_path"

        private const val TAG = "YQHLibboxVpn"
        private const val CHANNEL_ID = "yuqianhe_vpn"
        private const val NOTIFICATION_ID = 10086

        @Volatile
        private var tunFd: ParcelFileDescriptor? = null

        @Volatile
        private var running: Boolean = false

        @Volatile
        private var lastError: String? = null

        @Volatile
        private var currentConfigPath: String? = null

        @Volatile
        private var setupDone: Boolean = false

        @Volatile
        private var lastTunDnsServer: String? = null

        @Volatile
        private var lastUpstreamInterface: String? = null

        private val setupLock = Any()

        fun isRunning(): Boolean = running

        fun getLastError(): String? = lastError

        fun getCurrentConfigPath(): String? = currentConfigPath

        fun getLastTunDnsServer(): String? = lastTunDnsServer

        fun getLastUpstreamInterface(): String? = lastUpstreamInterface

        fun clearLastError() {
            lastError = null
        }
    }

    private val connectivity by lazy {
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }
    private val wifiManager by lazy {
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }
    private val defaultNetworkMonitor by lazy {
        AndroidDefaultNetworkMonitor(connectivity)
    }
    private val localResolver by lazy {
        AndroidLocalResolver(defaultNetworkMonitor)
    }

    @Volatile
    private var commandServer: CommandServer? = null

    override fun onBind(intent: Intent): IBinder {
        val binder = super.onBind(intent)
        return binder ?: BinderStub()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
                if (configPath.isNullOrBlank()) {
                    lastError = "missing config path"
                    stopVpn()
                    return START_NOT_STICKY
                }
                currentConfigPath = configPath
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification("宇千鹤连接中", "Android 真 TUN 模式启动中"),
                )
                startEngine(configPath)
                return START_STICKY
            }

            else -> return START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        stopCurrentFd()
        closeCommandServer()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    private fun startEngine(configPath: String) {
        thread(name = "yuqianhe-libbox-start") {
            try {
                lastError = null
                ensureLibboxSetup()
                defaultNetworkMonitor.start()
                val server = ensureCommandServer()
                val configText = File(configPath).readText()
                server.startOrReloadService(
                    configText,
                    OverrideOptions().apply {
                        autoRedirect = false
                    },
                )
                running = true
                lastError = null
                currentConfigPath = configPath
                updateForeground("宇千鹤已连接", "Android 真 TUN 代理运行中")
            } catch (e: Exception) {
                running = false
                lastError = e.message ?: e.toString()
                Log.e(TAG, "startEngine failed", e)
                updateForeground("宇千鹤连接失败", lastError ?: "未知错误")
                stopVpn()
            }
        }
    }

    private fun ensureLibboxSetup() {
        synchronized(setupLock) {
            if (setupDone) {
                return
            }
            val baseDir = File(filesDir, "libbox")
            val workDir = File(filesDir, "singbox_work")
            val tempDir = File(cacheDir, "singbox_tmp")
            baseDir.mkdirs()
            workDir.mkdirs()
            tempDir.mkdirs()
            Libbox.setup(
                SetupOptions().apply {
                    basePath = baseDir.absolutePath
                    workingPath = workDir.absolutePath
                    tempPath = tempDir.absolutePath
                    fixAndroidStack = true
                    commandServerListenPort = 0
                    commandServerSecret = ""
                    logMaxLines = 800
                    debug = true
                },
            )
            Libbox.touch()
            runCatching {
                Libbox.redirectStderr(File(baseDir, "stderr.log").absolutePath)
            }
            setupDone = true
        }
    }

    private fun ensureCommandServer(): CommandServer {
        val current = commandServer
        if (current != null) {
            return current
        }
        synchronized(this) {
            val again = commandServer
            if (again != null) {
                return again
            }
            val created = Libbox.newCommandServer(this, this)
            created.start()
            commandServer = created
            return created
        }
    }

    private fun stopVpn() {
        running = false
        stopCurrentFd()
        closeCommandServer()
        defaultNetworkMonitor.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun closeCommandServer() {
        val server = commandServer
        commandServer = null
        if (server != null) {
            runCatching { server.closeService() }
            runCatching { server.close() }
        }
    }

    private fun stopCurrentFd() {
        try {
            tunFd?.close()
        } catch (_: Exception) {
        }
        tunFd = null
    }

    private fun updateForeground(title: String, text: String) {
        val notification = buildNotification(title, text)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(title: String, text: String): Notification {
        ensureChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "宇千鹤 VPN",
            NotificationManager.IMPORTANCE_LOW,
        )
        nm.createNotificationChannel(channel)
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun clearDNSCache() {
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        defaultNetworkMonitor.setListener(null)
    }

    override fun closeNeighborMonitor(listener: NeighborUpdateListener) {
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return ConnectionOwner()
        }
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid <= 0) {
            return ConnectionOwner()
        }
        return ConnectionOwner().apply {
            userId = uid
            userName = packageManager.getPackagesForUid(uid)?.firstOrNull() ?: ""
        }
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        val networkInterfaces = try {
            NetworkInterface.getNetworkInterfaces().toList()
        } catch (_: Exception) {
            emptyList()
        }
        for (network in connectivity.allNetworks) {
            val linkProperties = connectivity.getLinkProperties(network) ?: continue
            val caps = connectivity.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                continue
            }
            val name = linkProperties.interfaceName ?: continue
            val networkInterface = networkInterfaces.firstOrNull { it.name == name } ?: continue
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = name
            boxInterface.index = networkInterface.index
            boxInterface.mtu = runCatching { networkInterface.mtu }.getOrDefault(1500)
            boxInterface.addresses = StringArray(
                networkInterface.interfaceAddresses.mapNotNull { it.toPrefix() },
            )
            boxInterface.dnsServer = StringArray(
                linkProperties.dnsServers.mapNotNull { it.hostAddress },
            )
            boxInterface.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            var flags = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (networkInterface.isLoopback) {
                flags = flags or OsConstants.IFF_LOOPBACK
            }
            if (networkInterface.isPointToPoint) {
                flags = flags or OsConstants.IFF_POINTOPOINT
            }
            if (networkInterface.supportsMulticast()) {
                flags = flags or OsConstants.IFF_MULTICAST
            }
            boxInterface.flags = flags
            boxInterface.metered =
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            interfaces.add(boxInterface)
        }
        return InterfaceArray(interfaces)
    }

    override fun includeAllNetworks(): Boolean = false

    override fun localDNSTransport(): LocalDNSTransport? = localResolver

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) {
            error("android: missing vpn permission")
        }
        stopCurrentFd()
        val builder = Builder()
            .setSession("宇千鹤")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        val inet4AddressList = mutableListOf<Pair<String, Int>>()
        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            val address = inet4Address.next()
            val host = address.address()
            val prefix = address.prefix()
            inet4AddressList.add(host to prefix)
            builder.addAddress(host, prefix)
        }

        val inet6AddressList = mutableListOf<Pair<String, Int>>()
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            val address = inet6Address.next()
            val host = address.address()
            val prefix = address.prefix()
            inet6AddressList.add(host to prefix)
            builder.addAddress(host, prefix)
        }

        if (options.autoRoute) {
            val dnsServer = runCatching { options.dnsServerAddress.value }.getOrDefault("")
            val vpnDnsServers = linkedSetOf<String>()
            if (dnsServer.isNotEmpty()) {
                vpnDnsServers.add(dnsServer)
            } else {
                val activeNetwork = defaultNetworkMonitor.require()
                val activeDnsServers = runCatching {
                    connectivity.getLinkProperties(activeNetwork)
                        ?.dnsServers
                        ?.mapNotNull { it.hostAddress ?: it.hostName }
                        .orEmpty()
                }.getOrDefault(emptyList())
                vpnDnsServers.addAll(activeDnsServers.filter { it.isNotBlank() })
                if (vpnDnsServers.isEmpty()) {
                    vpnDnsServers.add("1.1.1.1")
                }
            }
            for (server in vpnDnsServers) {
                builder.addDnsServer(server)
            }
            lastTunDnsServer = vpnDnsServers.joinToString(",")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4Routes = options.inet4RouteAddress
                var hasInet4Route = false
                while (inet4Routes.hasNext()) {
                    hasInet4Route = true
                    val route = inet4Routes.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                if (!hasInet4Route && inet4AddressList.isNotEmpty()) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6Routes = options.inet6RouteAddress
                var hasInet6Route = false
                while (inet6Routes.hasNext()) {
                    hasInet6Route = true
                    val route = inet6Routes.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                if (!hasInet6Route && inet6AddressList.isNotEmpty()) {
                    builder.addRoute("::", 0)
                }
            } else {
                val inet4Ranges = options.inet4RouteRange
                var hasInet4Route = false
                while (inet4Ranges.hasNext()) {
                    hasInet4Route = true
                    val route = inet4Ranges.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                if (!hasInet4Route && inet4AddressList.isNotEmpty()) {
                    builder.addRoute("0.0.0.0", 0)
                }
                val inet6Ranges = options.inet6RouteRange
                var hasInet6Route = false
                while (inet6Ranges.hasNext()) {
                    hasInet6Route = true
                    val route = inet6Ranges.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                if (!hasInet6Route && inet6AddressList.isNotEmpty()) {
                    builder.addRoute("::", 0)
                }
            }
        }

        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {
        }

        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                ),
            )
        }

        val pfd = builder.establish()
            ?: error("android: the application is not prepared or is revoked")
        tunFd = pfd
        return pfd.fd
    }

    override fun readWIFIState(): WIFIState? {
        @Suppress("DEPRECATION")
        val wifiInfo = wifiManager.connectionInfo ?: return null
        var ssid = wifiInfo.ssid ?: return null
        if (ssid == "<unknown ssid>") {
            return WIFIState("", "")
        }
        if (ssid.startsWith("\"") && ssid.endsWith("\"")) {
            ssid = ssid.substring(1, ssid.length - 1)
        }
        return WIFIState(ssid, wifiInfo.bssid ?: "")
    }

    override fun registerMyInterface(interfaceName: String) {
        lastUpstreamInterface = interfaceName
    }

    override fun sendNotification(notification: LibboxNotification) {
        val title = notification.title.ifEmpty { "宇千鹤通知" }
        val body = notification.body.ifEmpty { notification.subtitle ?: "" }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            notification.typeID,
            buildNotification(title, body),
        )
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        defaultNetworkMonitor.setListener(listener)
    }

    override fun startNeighborMonitor(listener: NeighborUpdateListener) {
        listener.updateNeighborTable(EmptyNeighborEntryIterator)
    }

    override fun systemCertificates(): StringIterator {
        val keyStore = KeyStore.getInstance("AndroidCAStore")
        keyStore.load(null, null)
        val certificates = mutableListOf<String>()
        val aliases = keyStore.aliases()
        while (aliases.hasMoreElements()) {
            val cert = keyStore.getCertificate(aliases.nextElement())
            certificates.add(
                "-----BEGIN CERTIFICATE-----\n" +
                    Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(cert.encoded) +
                    "\n-----END CERTIFICATE-----",
            )
        }
        return StringArray(certificates)
    }

    override fun underNetworkExtension(): Boolean = false

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun getSystemProxyStatus(): SystemProxyStatus {
        return SystemProxyStatus().apply {
            available = false
            enabled = false
        }
    }

    override fun serviceReload() {
        val path = currentConfigPath ?: return
        thread(name = "yuqianhe-libbox-reload") {
            try {
                val server = ensureCommandServer()
                server.startOrReloadService(
                    File(path).readText(),
                    OverrideOptions().apply {
                        autoRedirect = false
                    },
                )
                lastError = null
            } catch (e: Exception) {
                lastError = e.message ?: e.toString()
                Log.e(TAG, "serviceReload failed", e)
            }
        }
    }

    override fun serviceStop() {
        stopVpn()
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
    }

    override fun writeDebugMessage(message: String) {
        Log.d(TAG, message)
    }

    private class BinderStub : android.os.Binder()

    private class StringArray(values: List<String>) : StringIterator {
        private val items = values.toList()
        private var index = 0

        override fun len(): Int = items.size

        override fun hasNext(): Boolean = index < items.size

        override fun next(): String = items[index++]
    }

    private class InterfaceArray(values: List<LibboxNetworkInterface>) : NetworkInterfaceIterator {
        private val items = values.toList()
        private var index = 0

        override fun hasNext(): Boolean = index < items.size

        override fun next(): LibboxNetworkInterface = items[index++]
    }

    private object EmptyNeighborEntryIterator : NeighborEntryIterator {
        override fun hasNext(): Boolean = false
        override fun next(): NeighborEntry = throw NoSuchElementException("no neighbor entries")
    }

    private fun InterfaceAddress.toPrefix(): String? {
        val hostAddress = address.hostAddress ?: return null
        return if (address is Inet6Address) {
            "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
        } else {
            "$hostAddress/$networkPrefixLength"
        }
    }

    private class AndroidLocalResolver(
        private val monitor: AndroidDefaultNetworkMonitor,
    ) : LocalDNSTransport {
        override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        override fun exchange(ctx: ExchangeContext, message: ByteArray) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                ctx.errorCode(2)
                return
            }
            runBlocking {
                val network = monitor.require()
                if (network == null) {
                    ctx.errorCode(2)
                    return@runBlocking
                }
                suspendCoroutine { continuation ->
                    val signal = CancellationSignal()
                    ctx.onCancel(signal::cancel)
                    val callback = object : DnsResolver.Callback<ByteArray> {
                        override fun onAnswer(answer: ByteArray, rcode: Int) {
                            if (rcode == 0) {
                                ctx.rawSuccess(answer)
                            } else {
                                ctx.errorCode(rcode)
                            }
                            continuation.resume(Unit)
                        }

                        override fun onError(error: DnsResolver.DnsException) {
                            val cause = error.cause
                            if (cause is ErrnoException) {
                                ctx.errnoCode(cause.errno)
                                continuation.resume(Unit)
                                return
                            }
                            ctx.errorCode(2)
                            continuation.resume(Unit)
                        }
                    }
                    DnsResolver.getInstance().rawQuery(
                        network,
                        message,
                        DnsResolver.FLAG_NO_RETRY,
                        Dispatchers.IO.asExecutor(),
                        signal,
                        callback,
                    )
                }
            }
        }

        override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
            runBlocking {
                val activeNetwork = monitor.require()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && activeNetwork != null) {
                    suspendCoroutine { continuation ->
                        val signal = CancellationSignal()
                        ctx.onCancel(signal::cancel)
                        val callback = object : DnsResolver.Callback<Collection<InetAddress>> {
                            override fun onAnswer(answer: Collection<InetAddress>, rcode: Int) {
                                if (rcode == 0) {
                                    ctx.success(
                                        answer.mapNotNull { it.hostAddress }.joinToString("\n"),
                                    )
                                } else {
                                    ctx.errorCode(rcode)
                                }
                                continuation.resume(Unit)
                            }

                            override fun onError(error: DnsResolver.DnsException) {
                                val cause = error.cause
                                if (cause is ErrnoException) {
                                    ctx.errnoCode(cause.errno)
                                    continuation.resume(Unit)
                                    return
                                }
                                ctx.errorCode(2)
                                continuation.resume(Unit)
                            }
                        }
                        val type = when {
                            network.endsWith("4") -> DnsResolver.TYPE_A
                            network.endsWith("6") -> DnsResolver.TYPE_AAAA
                            else -> null
                        }
                        if (type != null) {
                            DnsResolver.getInstance().query(
                                activeNetwork,
                                domain,
                                type,
                                DnsResolver.FLAG_NO_RETRY,
                                Dispatchers.IO.asExecutor(),
                                signal,
                                callback,
                            )
                        } else {
                            DnsResolver.getInstance().query(
                                activeNetwork,
                                domain,
                                DnsResolver.FLAG_NO_RETRY,
                                Dispatchers.IO.asExecutor(),
                                signal,
                                callback,
                            )
                        }
                    }
                    return@runBlocking
                }

                val answer = try {
                    InetAddress.getAllByName(domain)
                } catch (_: UnknownHostException) {
                    ctx.errorCode(3)
                    return@runBlocking
                }
                ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
            }
        }
    }

    private class AndroidDefaultNetworkMonitor(
        private val connectivity: ConnectivityManager,
    ) {
        @Volatile
        private var defaultNetwork: Network? = null

        @Volatile
        private var listener: InterfaceUpdateListener? = null

        private var started = false

        private val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                refresh()
            }

            override fun onLost(network: Network) {
                refresh()
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                refresh()
            }
        }

        fun start() {
            refresh()
            if (started) {
                return
            }
            started = true
            runCatching {
                connectivity.registerDefaultNetworkCallback(callback)
            }.onFailure {
                started = false
            }
            refresh()
        }

        fun stop() {
            if (started) {
                runCatching {
                    connectivity.unregisterNetworkCallback(callback)
                }
            }
            started = false
            defaultNetwork = null
            listener?.updateDefaultInterface("", -1, false, false)
        }

        fun require(): Network? {
            val current = pickUpstreamNetwork()
            if (current != null) {
                defaultNetwork = current
                return current
            }
            return defaultNetwork
        }

        fun setListener(listener: InterfaceUpdateListener?) {
            this.listener = listener
            notifyListener(require())
        }

        private fun refresh() {
            val network = pickUpstreamNetwork()
            defaultNetwork = network
            notifyListener(network)
        }

        private fun pickUpstreamNetwork(): Network? {
            val active = connectivity.activeNetwork
            if (active != null) {
                val caps = connectivity.getNetworkCapabilities(active)
                if (caps != null &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                ) {
                    return active
                }
            }
            return connectivity.allNetworks.firstOrNull { network ->
                val caps = connectivity.getNetworkCapabilities(network) ?: return@firstOrNull false
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        }

        private fun notifyListener(network: Network?) {
            val listener = listener ?: return
            if (network == null) {
                lastUpstreamInterface = null
                listener.updateDefaultInterface("", -1, false, false)
                return
            }
            val interfaceName = connectivity.getLinkProperties(network)?.interfaceName ?: return
            lastUpstreamInterface = interfaceName
            repeat(10) {
                val index = runCatching {
                    NetworkInterface.getByName(interfaceName)?.index ?: -1
                }.getOrDefault(-1)
                if (index >= 0) {
                    listener.updateDefaultInterface(interfaceName, index, false, false)
                    return
                }
                Thread.sleep(100)
            }
            listener.updateDefaultInterface(interfaceName, -1, false, false)
        }
    }
}
