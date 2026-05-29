package com.freenet.vpn

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.widget.Toast
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.CopyOnWriteArrayList

object LogManager {
    private val _logs = CopyOnWriteArrayList<String>()
    
    private val _logsFlow = MutableStateFlow<List<String>>(emptyList())
    val logsFlow: StateFlow<List<String>> = _logsFlow.asStateFlow()

    private const val MAX_LOGS = 500
    private val dateFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun loadLogsFromFile(context: Context) {
        init(context)
        synchronized(this) {
            try {
                val file = java.io.File(context.filesDir, "freenet_vpn.log")
                if (file.exists()) {
                    val lines = file.readLines()
                    _logs.clear()
                    _logs.addAll(lines.takeLast(MAX_LOGS))
                    _logsFlow.value = _logs.toList()
                }
                Unit
            } catch (e: Exception) {
                android.util.Log.e("FreenetVPN", "Failed to load logs from file", e)
            }
        }
    }

    fun log(message: String) {
        val clean = message.trim()
        if (clean.isEmpty()) return
        
        val timestamp = dateFormat.format(Date())
        val entry = "[$timestamp] $clean"
        
        _logs.add(entry)
        while (_logs.size > MAX_LOGS) {
            _logs.removeAt(0)
        }
        _logsFlow.value = _logs.toList()
        
        // Write to log file for crash diagnostics with thread synchronization
        synchronized(this) {
            appContext?.let { ctx ->
                try {
                    val file = java.io.File(ctx.filesDir, "freenet_vpn.log")
                    file.appendText("$entry\n")
                    // Truncate file if it gets too large
                    if (file.length() > 500 * 1024) { // 500 KB limit
                        val lines = file.readLines()
                        file.writeText(lines.takeLast(MAX_LOGS).joinToString("\n") + "\n")
                    }
                    Unit
                } catch (e: Exception) {
                    android.util.Log.e("FreenetVPN", "Failed to write log to file", e)
                }
            }
        }
        
        // Also log to Android Logcat for debugging via ADB
        android.util.Log.d("FreenetVPN", clean)
    }

    fun clear() {
        _logs.clear()
        _logsFlow.value = emptyList()
        synchronized(this) {
            appContext?.let { ctx ->
                try {
                    java.io.File(ctx.filesDir, "freenet_vpn.log").delete()
                } catch (_: Exception) {}
            }
        }
        log("Günlük temizlendi.")
    }

    fun getFullLogText(): String {
        val header = buildString {
            appendLine("═══════════════════════════════════════")
            appendLine("  Freenet VPN - Hata Raporu")
            appendLine("  Tarih: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date())}")
            appendLine("  Cihaz: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("  Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("  Uygulama: v${getVersionName()}")
            appendLine("═══════════════════════════════════════")
            appendLine()
        }
        return header + _logs.joinToString("\n")
    }

    fun copyToClipboard(context: Context) {
        val text = getFullLogText()
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("Freenet VPN Logs", text)
        clipboard.setPrimaryClip(clip)
        Toast.makeText(context, "Loglar panoya kopyalandı ✓", Toast.LENGTH_SHORT).show()
    }

    private var versionName: String = "1.0.0"
    
    fun setVersionName(version: String) {
        versionName = version
    }
    
    private fun getVersionName(): String = versionName

    /**
     * Logs device & app info at startup for diagnostics
     */
    fun logSystemInfo() {
        log("═══ Sistem Bilgisi ═══")
        log("Cihaz: ${Build.MANUFACTURER} ${Build.MODEL}")
        log("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        log("ABI: ${Build.SUPPORTED_ABIS.joinToString(", ")}")
        log("Uygulama: v$versionName")
        log("═══════════════════════")
    }
}
