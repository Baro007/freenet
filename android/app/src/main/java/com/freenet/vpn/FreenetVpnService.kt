package com.freenet.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import io.nekohasekai.libbox.*

class FreenetVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    private var commandServer: CommandServer? = null
    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        LogManager.init(this)
        val action = intent?.action
        LogManager.log("[Service] onStartCommand: action=$action")
        
        if (action == ACTION_STOP) {
            stopVpn()
            stopSelf()
            return START_NOT_STICKY
        }
        
        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config != null) {
            startVpn(config)
        } else {
            LogManager.log("[Service] UYARI: Config null geldi, VPN başlatılamıyor.")
        }
        
        return START_STICKY
    }

    private fun startVpn(config: String) {
        try {
            LogManager.log("[Service] VPN başlatma süreci başladı...")
            stopVpn()
            
            // Setup Libbox
            LogManager.log("[Service] Libbox ortamı hazırlanıyor...")
            LogManager.log("[Service]   basePath: ${filesDir.absolutePath}")
            LogManager.log("[Service]   tempPath: ${cacheDir.absolutePath}")
            
            val options = SetupOptions()
            options.setBasePath(filesDir.absolutePath)
            options.setWorkingPath(filesDir.absolutePath)
            options.setTempPath(cacheDir.absolutePath)
            options.setDebug(true)
            Libbox.setup(options)
            LogManager.log("[Service] Libbox.setup() tamamlandı.")
            
            // Validate config before starting
            LogManager.log("[Service] Config doğrulanıyor...")
            LogManager.log("[Service] Config boyutu: ${config.length} karakter")
            try {
                val cs = Libbox.newCommandServer(this, this)
                cs.checkConfig(config)
                cs.close()
                LogManager.log("[Service] ✓ Config doğrulaması başarılı.")
            } catch (e: Exception) {
                LogManager.log("[Service] ✗ Config doğrulama HATASI: ${e.javaClass.simpleName}: ${e.message}")
                LogManager.log("[Service] Config içeriği:")
                // Log config lines for debugging
                config.lines().forEachIndexed { i, line ->
                    LogManager.log("[Config:${i+1}] $line")
                }
                throw e
            }
            
            // Create command server
            LogManager.log("[Service] CommandServer oluşturuluyor...")
            commandServer = Libbox.newCommandServer(this, this)
            commandServer?.start()
            LogManager.log("[Service] CommandServer başlatıldı.")
            
            // Start service with config
            LogManager.log("[Service] Servis başlatılıyor (startOrReloadService)...")
            val overrideOptions = OverrideOptions()
            commandServer?.startOrReloadService(config, overrideOptions)
            
            LogManager.log("[Service] ✓ Freenet VPN aktif!")
            
            // Start foreground notification
            startForegroundNotification()
            LogManager.log("[Service] Foreground bildirim oluşturuldu.")
            
        } catch (e: Exception) {
            LogManager.log("[Service] ✗ HATA: VPN başlatılamadı!")
            LogManager.log("[Service]   Hata tipi: ${e.javaClass.simpleName}")
            LogManager.log("[Service]   Hata mesajı: ${e.localizedMessage}")
            LogManager.log("[Service]   Stack trace:")
            e.stackTrace.take(10).forEach { frame ->
                LogManager.log("[Service]     $frame")
            }
            e.cause?.let { cause ->
                LogManager.log("[Service]   Caused by: ${cause.javaClass.simpleName}: ${cause.message}")
            }
            stopVpn()
            stopSelf()
        }
    }

    private fun stopVpn() {
        LogManager.log("[Service] VPN durduruluyor...")
        try {
            commandServer?.closeService()
            commandServer?.close()
            commandServer = null
            LogManager.log("[Service] CommandServer kapatıldı.")
        } catch (e: Exception) {
            LogManager.log("[Service] CommandServer kapatma hatası: ${e.message}")
        }
        
        try {
            vpnInterface?.close()
            vpnInterface = null
            LogManager.log("[Service] VPN tüneli kapatıldı.")
        } catch (e: Exception) {
            LogManager.log("[Service] Tünel kapatma hatası: ${e.message}")
        }
        
        stopForeground(true)
        LogManager.log("[Service] Bağlantı durduruldu.")
    }

    override fun onDestroy() {
        LogManager.log("[Service] Service onDestroy()")
        stopVpn()
        super.onDestroy()
    }

    // ═══════════════════════════════════════
    // PlatformInterface Implementation
    // ═══════════════════════════════════════
    
    override fun openTun(options: TunOptions): Int {
        LogManager.log("[Tünel] openTun() çağrıldı — TUN arayüzü oluşturuluyor...")
        try {
            val builder = Builder()
            builder.setSession("Freenet VPN")
            
            val mtu = options.getMTU()
            val effectiveMtu = if (mtu > 0) mtu else 1500
            builder.setMtu(effectiveMtu)
            LogManager.log("[Tünel] MTU: $effectiveMtu")
            
            // IPv4 Addresses
            var addressCount = 0
            val inet4Address = options.getInet4Address()
            if (inet4Address != null) {
                while (inet4Address.hasNext()) {
                    val route = inet4Address.next()
                    builder.addAddress(route.address(), route.prefix())
                    LogManager.log("[Tünel] IPv4 adres: ${route.address()}/${route.prefix()}")
                    addressCount++
                }
            }
            
            val inet6Address = options.getInet6Address()
            if (inet6Address != null) {
                while (inet6Address.hasNext()) {
                    val route = inet6Address.next()
                    builder.addAddress(route.address(), route.prefix())
                    LogManager.log("[Tünel] IPv6 adres: ${route.address()}/${route.prefix()}")
                    addressCount++
                }
            }
            
            if (addressCount == 0) {
                LogManager.log("[Tünel] UYARI: Hiçbir adres atanmadı! Varsayılan adresler ekleniyor...")
                builder.addAddress("172.19.0.1", 30)
                builder.addAddress("fdfe:dcba:9876::1", 126)
            }
            
            // IPv4 Routes
            val inet4Route = options.getInet4RouteAddress()
            var addedDefaultRoute4 = false
            var routeCount = 0
            if (inet4Route != null) {
                while (inet4Route.hasNext()) {
                    val route = inet4Route.next()
                    builder.addRoute(route.address(), route.prefix())
                    routeCount++
                    if (route.address() == "0.0.0.0" && route.prefix() == 0) {
                        addedDefaultRoute4 = true
                    }
                }
            }
            if (!addedDefaultRoute4) {
                builder.addRoute("0.0.0.0", 0)
                routeCount++
            }
            
            // IPv6 Routes
            val inet6Route = options.getInet6RouteAddress()
            var addedDefaultRoute6 = false
            if (inet6Route != null) {
                while (inet6Route.hasNext()) {
                    val route = inet6Route.next()
                    builder.addRoute(route.address(), route.prefix())
                    routeCount++
                    if (route.address() == "::" && route.prefix() == 0) {
                        addedDefaultRoute6 = true
                    }
                }
            }
            if (!addedDefaultRoute6) {
                builder.addRoute("::", 0)
                routeCount++
            }
            LogManager.log("[Tünel] Toplam rota sayısı: $routeCount")
            
            // DNS Servers
            val dnsBox = options.getDNSServerAddress()
            if (dnsBox != null && dnsBox.getValue().isNotEmpty()) {
                builder.addDnsServer(dnsBox.getValue())
                LogManager.log("[Tünel] DNS sunucusu: ${dnsBox.getValue()}")
            } else {
                builder.addDnsServer("1.1.1.1")
                LogManager.log("[Tünel] DNS sunucusu (varsayılan): 1.1.1.1")
            }
            
            // Exclude / Include apps
            // Always exclude our own app to prevent routing loops and "operation not permitted" socket errors
            try {
                builder.addDisallowedApplication(packageName)
                LogManager.log("[Tünel] Kendi paketimiz ($packageName) VPN tüneli dışına çıkarıldı.")
            } catch (e: Exception) {
                LogManager.log("[Tünel] Kendi paketimizi dışlama hatası: ${e.message}")
            }

            val excludeIterator = options.getExcludePackage()
            if (excludeIterator != null) {
                while (excludeIterator.hasNext()) {
                    val pkg = excludeIterator.next()
                    if (pkg == packageName) continue // Avoid adding twice
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (e: Exception) { /* Package not installed */ }
                }
            }
            
            val includeIterator = options.getIncludePackage()
            if (includeIterator != null) {
                while (includeIterator.hasNext()) {
                    val pkg = includeIterator.next()
                    try {
                        builder.addAllowedApplication(pkg)
                    } catch (e: Exception) { /* Package not installed */ }
                }
            }
            
            val pfd = builder.establish()
            vpnInterface = pfd
            if (pfd != null) {
                LogManager.log("[Tünel] ✓ TUN arayüzü başarıyla kuruldu. fd=${pfd.fd}")
                return pfd.fd
            } else {
                LogManager.log("[Tünel] ✗ HATA: builder.establish() null döndürdü!")
                LogManager.log("[Tünel]   VPN izni verilmemiş olabilir.")
            }
        } catch (e: Exception) {
            LogManager.log("[Tünel] ✗ TUN kurulum HATASI: ${e.javaClass.simpleName}: ${e.localizedMessage}")
            e.stackTrace.take(5).forEach { frame ->
                LogManager.log("[Tünel]   $frame")
            }
        }
        return -1
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        LogManager.log("[Platform] autoDetectInterfaceControl(fd=$fd) — protect()")
        protect(fd)
    }

    override fun sendNotification(notification: Notification?) {
        LogManager.log("[Platform] Bildirim: ${notification?.toString() ?: "boş"}")
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = false
    override fun clearDNSCache() {
        LogManager.log("[Platform] clearDNSCache() çağrıldı")
    }
    override fun findConnectionOwner(p0: Int, p1: String?, p2: Int, p3: String?, p4: Int): ConnectionOwner? = null
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        LogManager.log("[Platform] startDefaultInterfaceMonitor() çağrıldı")
    }
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        LogManager.log("[Platform] closeDefaultInterfaceMonitor() çağrıldı")
    }
    override fun includeAllNetworks(): Boolean = false
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun readWIFIState(): WIFIState? = null
    override fun systemCertificates(): StringIterator? = null
    override fun underNetworkExtension(): Boolean = false
    override fun useProcFS(): Boolean = false
    override fun getInterfaces(): NetworkInterfaceIterator? = null

    // ═══════════════════════════════════════
    // CommandServerHandler Implementation
    // ═══════════════════════════════════════
    
    override fun serviceStop() {
        LogManager.log("[Handler] serviceStop() çağrıldı — servis durduruluyor")
        stopVpn()
        stopSelf()
    }

    override fun serviceReload() {
        LogManager.log("[Handler] serviceReload() çağrıldı")
    }

    override fun writeDebugMessage(message: String?) {
        if (message != null) {
            LogManager.log("[sing-box] $message")
        }
    }

    override fun setSystemProxyEnabled(enabled: Boolean) {
        LogManager.log("[Platform] setSystemProxyEnabled($enabled)")
    }

    override fun getSystemProxyStatus(): SystemProxyStatus? = null

    // ═══════════════════════════════════════
    // Foreground Notification
    // ═══════════════════════════════════════
    
    private fun startForegroundNotification() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID,
                "Freenet VPN",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.createNotificationChannel(channel)
        }

        val pendingIntent = android.app.PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = androidx.core.app.NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Freenet VPN")
            .setContentText("Sansürsüz ve özgür internet aktif.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                if (android.os.Build.VERSION.SDK_INT >= 34) {
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                } else {
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE
                }
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_START = "com.freenet.vpn.START"
        const val ACTION_STOP = "com.freenet.vpn.STOP"
        const val EXTRA_CONFIG = "com.freenet.vpn.CONFIG"
        
        private const val CHANNEL_ID = "freenet_vpn_channel"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context, configuration: String) {
            LogManager.log("[Service] start() çağrıldı, config boyutu: ${configuration.length}")
            val intent = Intent(context, FreenetVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CONFIG, configuration)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            LogManager.log("[Service] stop() çağrıldı")
            val intent = Intent(context, FreenetVpnService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
