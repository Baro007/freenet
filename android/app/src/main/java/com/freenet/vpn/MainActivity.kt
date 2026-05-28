package com.freenet.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyPairGenerator

enum class AppMode(val title: String, val desc: String, val accentColor: Color) {
    DPI("DPI Modu (Yerel)", "TCP el sıkışmasını bölerek sansürü sıfır hız kaybıyla aşar.", Color(0xFFFF9800)),
    WARP("WARP Modu (Tünel)", "Tüm trafiği Cloudflare WireGuard tünelinden geçirir.", Color(0xFF4CAF50)),
    SINGBOX("sing-box (Gelişmiş)", "DoH ve TLS fragmantasyon tüneli ile ağır sansürleri aşar.", Color(0xFF00BCD4))
}

class MainActivity : ComponentActivity() {

    private val vpnPrepareLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            // Permission granted, start VPN
            startVpnService()
        } else {
            LogManager.log("Hata: VPN izni verilmedi.")
        }
    }

    private var isConnected = mutableStateOf(false)
    private var selectedMode = mutableStateOf(AppMode.DPI)
    private var isRegisteringWarp = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Load initial state
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        isConnected.value = prefs.getBoolean("is_connected", false)
        selectedMode.value = AppMode.valueOf(prefs.getString("selected_mode", AppMode.DPI.name) ?: AppMode.DPI.name)

        setContent {
            FreenetTheme {
                MainScreen(
                    isConnected = isConnected.value,
                    selectedMode = selectedMode.value,
                    isRegisteringWarp = isRegisteringWarp.value,
                    onModeSelected = {
                        if (!isConnected.value) {
                            selectedMode.value = it
                            prefs.edit().putString("selected_mode", it.name).apply()
                        }
                    },
                    onToggleConnection = {
                        if (isConnected.value) {
                            stopVpnService()
                        } else {
                            prepareAndStartVpn()
                        }
                    }
                )
            }
        }
    }

    private fun prepareAndStartVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            vpnPrepareLauncher.launch(intent)
        } else {
            startVpnService()
        }
    }

    private fun startVpnService() {
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        
        if (selectedMode.value == AppMode.WARP) {
            val hasWarp = prefs.contains("warp_private_key")
            if (!hasWarp) {
                // Register WARP profile first
                isRegisteringWarp.value = true
                LogManager.log("Cloudflare WARP profili oluşturuluyor...")
                
                lifecycleScope.launch {
                    val result = registerWarp()
                    isRegisteringWarp.value = false
                    if (result) {
                        launchVpnService()
                    } else {
                        LogManager.log("Hata: WARP profili oluşturulamadı.")
                    }
                }
                return
            }
        }
        
        launchVpnService()
    }

    private fun launchVpnService() {
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        val config = when (selectedMode.value) {
            AppMode.DPI -> VpnConfigGenerator.generateDpiConfig(0)
            AppMode.SINGBOX -> VpnConfigGenerator.generateSingBoxConfig(0)
            AppMode.WARP -> {
                val privateKey = prefs.getString("warp_private_key", "") ?: ""
                val localIPv4 = prefs.getString("warp_local_ipv4", "172.16.0.2/32") ?: "172.16.0.2/32"
                val localIPv6 = prefs.getString("warp_local_ipv6", "") ?: ""
                VpnConfigGenerator.generateWarpConfig(0, privateKey, localIPv4, localIPv6)
            }
        }
        
        LogManager.log("Bağlantı başlatılıyor: ${selectedMode.value.title}")
        FreenetVpnService.start(this, config)
        
        isConnected.value = true
        prefs.edit().putBoolean("is_connected", true).apply()
    }

    private fun stopVpnService() {
        LogManager.log("Bağlantı durduruluyor...")
        FreenetVpnService.stop(this)
        
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        isConnected.value = false
        prefs.edit().putBoolean("is_connected", false).apply()
    }

    private val lifecycleScope get() = (this as ComponentActivity).lifecycleScope

    private suspend fun registerWarp(): Boolean = withContext(Dispatchers.IO) {
        try {
            // Generate Curve25519 Keypair using built-in Android KeyPairGenerator
            val kpg = KeyPairGenerator.getInstance("X25519")
            val kp = kpg.generateKeyPair()
            
            // Extract raw keys (remove DER headers)
            val rawPrivate = kp.private.encoded.sliceArray(16 until 48)
            val rawPublic = kp.public.encoded.sliceArray(12 until 44)
            
            val privateKeyBase64 = Base64.encodeToString(rawPrivate, Base64.NO_WRAP)
            val publicKeyBase64 = Base64.encodeToString(rawPublic, Base64.NO_WRAP)
            
            val url = URL("https://api.cloudflareclient.com/v0a2158/reg")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("User-Agent", "okhttp/3.12.1")
            conn.doOutput = true
            
            val body = JSONObject().apply {
                put("key", publicKeyBase64)
                put("install_id", "")
                put("fcm_token", "")
                put("referrer", "")
                put("warp_enabled", true)
                put("tos", "2020-05-18T00:00:00.000+02:00")
                put("type", "Android")
                put("locale", "en_US")
            }
            
            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
            
            if (conn.responseCode == 200) {
                val responseStr = conn.inputStream.bufferedReader().use { it.readText() }
                val response = JSONObject(responseStr)
                
                val config = response.getJSONObject("config")
                val clientInterface = config.getJSONObject("interface")
                val addresses = clientInterface.getJSONArray("addresses")
                
                var localIPv4 = "172.16.0.2/32"
                var localIPv6 = ""
                for (i in 0 until addresses.length()) {
                    val addr = addresses.getString(i)
                    if (addr.contains(".")) {
                        localIPv4 = addr
                    } else if (addr.contains(":")) {
                        localIPv6 = addr
                    }
                }
                
                val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putString("warp_private_key", privateKeyBase64)
                    putString("warp_local_ipv4", localIPv4)
                    putString("warp_local_ipv6", localIPv6)
                    apply()
                }
                
                LogManager.log("WARP kaydı başarılı! IP: $localIPv4")
                return@withContext true
            } else {
                LogManager.log("WARP kaydı başarısız (Kod: ${conn.responseCode})")
            }
        } catch (e: Exception) {
            LogManager.log("WARP kayıt hatası: ${e.localizedMessage}")
        }
        return@withContext false
    }
}

// Simple extension helper for coroutines in ComponentActivity
private val ComponentActivity.lifecycleScope get() = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.Main)

@Composable
fun FreenetTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFFFF9800),
            background = Color(0xFF0F1013),
            surface = Color(0xFF16171D)
        ),
        content = content
    )
}

@Composable
fun MainScreen(
    isConnected: Boolean,
    selectedMode: AppMode,
    isRegisteringWarp: Boolean,
    onModeSelected: (AppMode) -> Unit,
    onToggleConnection: () -> Unit
) {
    val logs by LogManager.logsFlow.collectAsState()
    
    val pulseTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by pulseTransition.animateFloat(
        initialValue = 1f,
        targetValue = if (isConnected) 1.08f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "scale"
    )

    val buttonGlowColor by animateColorAsState(
        targetValue = if (isConnected) selectedMode.accentColor else Color(0x33FFFFFF),
        animationSpec = tween(500),
        label = "glow"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(Color(0xFF0C0D12), Color(0xFF14161F))
                )
            )
            .padding(16.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "freenet",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = if (isConnected) selectedMode.accentColor.copy(alpha = 0.15f) else Color(0xFF22242D),
                    border = BorderStroke(1.dp, if (isConnected) selectedMode.accentColor.copy(alpha = 0.4f) else Color(0xFF333644))
                ) {
                    Text(
                        text = if (isConnected) "AKTİF" else "KAPALI",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isConnected) selectedMode.accentColor else Color.Gray,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Pulse Glow Button in Center
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(160.dp)
                    .clickable { if (!isRegisteringWarp) onToggleConnection() }
            ) {
                // Background glow
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .blur(20.dp)
                        .background(buttonGlowColor.copy(alpha = if (isConnected) 0.5f else 0.1f), CircleShape)
                )

                // Outer pulsing ring
                Box(
                    modifier = Modifier
                        .size(120.dp * pulseScale)
                        .border(
                            BorderStroke(
                                2.dp,
                                if (isConnected) selectedMode.accentColor.copy(alpha = 0.7f) else Color(0xFF333644)
                            ),
                            CircleShape
                        )
                )

                // Main Circle Button
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(104.dp)
                        .shadow(24.dp, CircleShape)
                        .clip(CircleShape)
                        .background(
                            Brush.linearGradient(
                                colors = listOf(Color(0xFF1F222F), Color(0xFF12141C))
                            )
                        )
                ) {
                    if (isRegisteringWarp) {
                        CircularProgressIndicator(color = selectedMode.accentColor)
                    } else {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = "Toggle",
                            tint = if (isConnected) selectedMode.accentColor else Color.White,
                            modifier = Modifier.size(36.dp)
                        )
                    }
                }
            }

            Text(
                text = if (isConnected) "Güvenli bağlantı aktif." else "Bağlanmak için kalkan butonuna basın.",
                fontSize = 12.sp,
                color = Color.Gray,
                modifier = Modifier.padding(top = 10.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Modes Section
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                AppMode.values().forEach { mode ->
                    val isModeSelected = selectedMode == mode
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (isModeSelected) mode.accentColor.copy(alpha = 0.08f) else Color(0xFF16171D))
                            .border(
                                BorderStroke(
                                    1.dp,
                                    if (isModeSelected) mode.accentColor.copy(alpha = 0.4f) else Color(0x1AFFFFFF)
                                ),
                                RoundedCornerShape(12.dp)
                            )
                            .clickable { onModeSelected(mode) }
                            .padding(10.dp),
                        contentAlignment = Alignment.TopStart
                    ) {
                        Column {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(mode.accentColor, CircleShape)
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = mode.name,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = mode.desc,
                                fontSize = 9.sp,
                                color = Color.Gray,
                                lineHeight = 11.sp
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Real-time Logs Console
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xFF08090C))
                    .border(BorderStroke(1.dp, Color(0xFF1A1C24)), RoundedCornerShape(16.dp))
            ) {
                // Console Header
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF0F1014))
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "CANLI SİSTEM GÜNLÜĞÜ",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.LightGray,
                        letterSpacing = 1.sp
                    )
                    
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = "Clear logs",
                        tint = Color.Gray,
                        modifier = Modifier
                            .size(16.dp)
                            .clickable { LogManager.clear() }
                    )
                }

                Divider(color = Color(0xFF1A1C24))

                // Logs list
                val listState = rememberLazyListState()
                LaunchedEffect(logs.size) {
                    if (logs.isNotEmpty()) {
                        listState.animateScrollToItem(logs.size - 1)
                    }
                }

                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(10.dp)
                ) {
                    itemsIndexed(logs) { index, log ->
                        val logColor = remember(log) {
                            val lower = log.lowercase()
                            when {
                                lower.contains("hata") || lower.contains("error") || lower.contains("fail") -> Color(0xFFEF5350)
                                lower.contains("warning") || lower.contains("uyarı") -> Color(0xFFFFB74D)
                                log.startsWith("---") -> Color(0xFF4DD0E1)
                                lower.contains("connected") || lower.contains("aktif") || lower.contains("başarılı") -> Color(0xFF81C784)
                                else -> Color.White.copy(alpha = 0.85f)
                            }
                        }
                        
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 2.dp)
                        ) {
                            Text(
                                text = String.format("%04d", index + 1),
                                fontFamily = FontFamily.Monospace,
                                fontSize = 10.sp,
                                color = Color.Gray.copy(alpha = 0.5f),
                                modifier = Modifier.width(32.dp)
                            )
                            Text(
                                text = log,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 10.sp,
                                color = logColor,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
        }
    }
}
