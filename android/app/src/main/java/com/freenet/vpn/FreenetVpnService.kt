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
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopVpn()
            stopSelf()
            return START_NOT_STICKY
        }
        
        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config != null) {
            startVpn(config)
        }
        
        return START_STICKY
    }

    private fun startVpn(config: String) {
        try {
            stopVpn()
            
            // Setup Libbox
            val options = SetupOptions()
            options.setBasePath(filesDir.absolutePath)
            options.setWorkingPath(filesDir.absolutePath)
            options.setTempPath(cacheDir.absolutePath)
            options.setDebug(true)
            Libbox.setup(options)
            
            // Create command server
            commandServer = Libbox.newCommandServer(this, this)
            commandServer?.start()
            
            // Start service with config
            val overrideOptions = OverrideOptions()
            commandServer?.startOrReloadService(config, overrideOptions)
            
            LogManager.log("Freenet VPN aktif.")
            
            // Start foreground
            startForegroundNotification()
        } catch (e: Exception) {
            LogManager.log("Hata: VPN başlatılamadı: ${e.localizedMessage}")
            stopVpn()
            stopSelf()
        }
    }

    private fun stopVpn() {
        try {
            commandServer?.closeService()
            commandServer?.close()
            commandServer = null
        } catch (e: Exception) {
            // Ignore
        }
        
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            // Ignore
        }
        
        stopForeground(true)
        LogManager.log("Bağlantı durduruldu.")
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    // PlatformInterface Implementation
    override fun openTun(options: TunOptions): Int {
        LogManager.log("Ağ tüneli oluşturuluyor...")
        try {
            val builder = Builder()
            builder.setSession("Freenet VPN")
            
            val mtu = options.getMTU()
            builder.setMtu(if (mtu > 0) mtu else 1500)
            
            // Addresses
            val inet4Address = options.getInet4Address()
            if (inet4Address != null) {
                while (inet4Address.hasNext()) {
                    val route = inet4Address.next()
                    builder.addAddress(route.address(), route.prefix())
                }
            }
            val inet6Address = options.getInet6Address()
            if (inet6Address != null) {
                while (inet6Address.hasNext()) {
                    val route = inet6Address.next()
                    builder.addAddress(route.address(), route.prefix())
                }
            }
            
            // Routes
            val inet4Route = options.getInet4RouteAddress()
            var addedDefaultRoute4 = false
            if (inet4Route != null) {
                while (inet4Route.hasNext()) {
                    val route = inet4Route.next()
                    builder.addRoute(route.address(), route.prefix())
                    if (route.address() == "0.0.0.0" && route.prefix() == 0) {
                        addedDefaultRoute4 = true
                    }
                }
            }
            if (!addedDefaultRoute4) {
                builder.addRoute("0.0.0.0", 0)
            }
            
            val inet6Route = options.getInet6RouteAddress()
            var addedDefaultRoute6 = false
            if (inet6Route != null) {
                while (inet6Route.hasNext()) {
                    val route = inet6Route.next()
                    builder.addRoute(route.address(), route.prefix())
                    if (route.address() == "::" && route.prefix() == 0) {
                        addedDefaultRoute6 = true
                    }
                }
            }
            if (!addedDefaultRoute6) {
                builder.addRoute("::", 0)
            }
            
            // DNS Servers
            val dnsBox = options.getDNSServerAddress()
            if (dnsBox != null && dnsBox.getValue().isNotEmpty()) {
                builder.addDnsServer(dnsBox.getValue())
            } else {
                builder.addDnsServer("1.1.1.1")
            }
            
            // App rules
            val excludeIterator = options.getExcludePackage()
            if (excludeIterator != null) {
                while (excludeIterator.hasNext()) {
                    val pkg = excludeIterator.next()
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (e: Exception) {
                        // Package not installed
                    }
                }
            }
            
            val includeIterator = options.getIncludePackage()
            if (includeIterator != null) {
                while (includeIterator.hasNext()) {
                    val pkg = includeIterator.next()
                    try {
                        builder.addAllowedApplication(pkg)
                    } catch (e: Exception) {
                        // Package not installed
                    }
                }
            }
            
            val pfd = builder.establish()
            vpnInterface = pfd
            if (pfd != null) {
                LogManager.log("Tünel başarıyla kuruldu.")
                return pfd.fd
            }
        } catch (e: Exception) {
            LogManager.log("Tünel kurulum hatası: ${e.localizedMessage}")
        }
        return -1
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun sendNotification(notification: Notification?) {
        LogManager.log("Bildirim: ${notification?.toString() ?: ""}")
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun clearDNSCache() {}

    override fun findConnectionOwner(p0: Int, p1: String?, p2: Int, p3: String?, p4: Int): ConnectionOwner? = null

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}

    override fun includeAllNetworks(): Boolean = false

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun readWIFIState(): WIFIState? = null

    override fun systemCertificates(): StringIterator? = null

    override fun underNetworkExtension(): Boolean = false

    override fun useProcFS(): Boolean = false

    override fun getInterfaces(): NetworkInterfaceIterator? = null

    // CommandServerHandler Implementation
    override fun serviceStop() {
        stopVpn()
        stopSelf()
    }

    override fun serviceReload() {}

    override fun writeDebugMessage(message: String?) {
        if (message != null) {
            LogManager.log(message)
        }
    }

    override fun setSystemProxyEnabled(enabled: Boolean) {}

    override fun getSystemProxyStatus(): SystemProxyStatus? = null

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
            val intent = Intent(context, FreenetVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CONFIG, configuration)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, FreenetVpnService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
