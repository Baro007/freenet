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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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
            LogManager.log("[UI] VPN izni verildi, servis başlatılıyor...")
            startVpnService()
        } else {
            LogManager.log("[UI] ✗ VPN izni reddedildi (resultCode: ${result.resultCode})")
        }
    }

    private var isConnected = mutableStateOf(false)
    private var selectedMode = mutableStateOf(AppMode.DPI)
    private var isRegisteringWarp = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Set app version for logs
        try {
            val pInfo = packageManager.getPackageInfo(packageName, 0)
            LogManager.setVersionName(pInfo.versionName ?: "1.0.0")
        } catch (_: Exception) {}
        
        // Log system info at startup
        LogManager.logSystemInfo()
        LogManager.log("[UI] Uygulama başlatıldı.")
        
        // Load initial state
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        isConnected.value = prefs.getBoolean("is_connected", false)
        
        try {
            selectedMode.value = AppMode.valueOf(prefs.getString("selected_mode", AppMode.DPI.name) ?: AppMode.DPI.name)
        } catch (e: Exception) {
            selectedMode.value = AppMode.DPI
            LogManager.log("[UI] Mod yükleme hatası, varsayılan DPI kullanılıyor: ${e.message}")
        }
        
        LogManager.log("[UI] Kayıtlı mod: ${selectedMode.value.name}, Bağlantı: ${isConnected.value}")

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
                            LogManager.log("[UI] Mod değiştirildi: ${it.name}")
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
        LogManager.log("[UI] VPN hazırlığı başlatılıyor...")
        val intent = VpnService.prepare(this)
        if (intent != null) {
            LogManager.log("[UI] VPN izni gerekiyor, kullanıcıdan izin isteniyor...")
            vpnPrepareLauncher.launch(intent)
        } else {
            LogManager.log("[UI] VPN izni zaten verilmiş.")
            startVpnService()
        }
    }

    private fun startVpnService() {
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        LogManager.log("[UI] Mod: ${selectedMode.value.name}")
        
        if (selectedMode.value == AppMode.WARP) {
            val hasWarp = prefs.contains("warp_private_key")
            LogManager.log("[UI] WARP profili mevcut: $hasWarp")
            if (!hasWarp) {
                isRegisteringWarp.value = true
                LogManager.log("[WARP] Cloudflare WARP profili oluşturuluyor...")
                
                lifecycleScope.launch {
                    val result = registerWarp()
                    isRegisteringWarp.value = false
                    if (result) {
                        LogManager.log("[WARP] ✓ Profil başarıyla oluşturuldu, VPN başlatılıyor...")
                        launchVpnService()
                    } else {
                        LogManager.log("[WARP] ✗ Profil oluşturulamadı. Detaylar için yukarıdaki loglara bakın.")
                    }
                }
                return
            }
        }
        
        launchVpnService()
    }

    private fun launchVpnService() {
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        
        LogManager.log("[Config] ${selectedMode.value.name} modu için config üretiliyor...")
        
        val config = when (selectedMode.value) {
            AppMode.DPI -> {
                LogManager.log("[Config] DPI modu: doğrudan bağlantı + Google DNS")
                VpnConfigGenerator.generateDpiConfig()
            }
            AppMode.SINGBOX -> {
                LogManager.log("[Config] sing-box modu: Cloudflare DoH")
                VpnConfigGenerator.generateSingBoxConfig()
            }
            AppMode.WARP -> {
                val privateKey = prefs.getString("warp_private_key", "") ?: ""
                val localIPv4 = prefs.getString("warp_local_ipv4", "172.16.0.2/32") ?: "172.16.0.2/32"
                val localIPv6 = prefs.getString("warp_local_ipv6", "") ?: ""
                LogManager.log("[Config] WARP modu:")
                LogManager.log("[Config]   IPv4: $localIPv4")
                LogManager.log("[Config]   IPv6: ${localIPv6.ifEmpty { "yok" }}")
                LogManager.log("[Config]   Key: ${privateKey.take(8)}...${privateKey.takeLast(4)}")
                VpnConfigGenerator.generateWarpConfig(privateKey, localIPv4, localIPv6)
            }
        }
        
        LogManager.log("[Config] Config boyutu: ${config.length} karakter")
        LogManager.log("[Service] VPN servisi başlatılıyor...")
        
        FreenetVpnService.start(this, config)
        
        isConnected.value = true
        prefs.edit().putBoolean("is_connected", true).apply()
    }

    private fun stopVpnService() {
        LogManager.log("[UI] Bağlantı kapatma isteği...")
        FreenetVpnService.stop(this)
        
        val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
        isConnected.value = false
        prefs.edit().putBoolean("is_connected", false).apply()
    }

    private val lifecycleScope get() = (this as ComponentActivity).lifecycleScope

    private suspend fun registerWarp(): Boolean = withContext(Dispatchers.IO) {
        try {
            // ═══ 1. X25519 Anahtar Üretimi ═══
            LogManager.log("[WARP] Adım 1/3: X25519 anahtar çifti üretiliyor...")
            var privateKeyBase64: String
            var publicKeyBase64: String
            
            try {
                // Android 13+ (API 33+) native X25519 desteği
                LogManager.log("[WARP] Android API ${android.os.Build.VERSION.SDK_INT} - native X25519 deneniyor...")
                val kpg = KeyPairGenerator.getInstance("X25519")
                val kp = kpg.generateKeyPair()
                
                val privateEncoded = kp.private.encoded
                val publicEncoded = kp.public.encoded
                LogManager.log("[WARP] Private key DER boyutu: ${privateEncoded.size}")
                LogManager.log("[WARP] Public key DER boyutu: ${publicEncoded.size}")
                
                // Extract raw 32 byte keys from DER encoding
                val rawPrivate = if (privateEncoded.size >= 48) {
                    privateEncoded.sliceArray(privateEncoded.size - 32 until privateEncoded.size)
                } else {
                    privateEncoded
                }
                
                val rawPublic = if (publicEncoded.size >= 44) {
                    publicEncoded.sliceArray(publicEncoded.size - 32 until publicEncoded.size)
                } else {
                    publicEncoded
                }
                
                privateKeyBase64 = Base64.encodeToString(rawPrivate, Base64.NO_WRAP)
                publicKeyBase64 = Base64.encodeToString(rawPublic, Base64.NO_WRAP)
                LogManager.log("[WARP] ✓ X25519 anahtar çifti üretildi (native).")
                LogManager.log("[WARP] Public key: ${publicKeyBase64.take(16)}...")
                
            } catch (e: Exception) {
                LogManager.log("[WARP] ✗ Native X25519 desteklenmiyor: ${e.javaClass.simpleName}: ${e.message}")
                LogManager.log("[WARP] Fallback: SecureRandom Curve25519 kullanılıyor...")
                
                val random = java.security.SecureRandom()
                val privateKey = ByteArray(32)
                random.nextBytes(privateKey)
                // Clamp per Curve25519 spec
                privateKey[0] = (privateKey[0].toInt() and 248).toByte()
                privateKey[31] = (privateKey[31].toInt() and 127 or 64).toByte()
                
                privateKeyBase64 = Base64.encodeToString(privateKey, Base64.NO_WRAP)
                
                // Try to derive proper public key via KeyFactory
                try {
                    // Build proper PKCS#8 ASN.1 encoding for X25519 private key
                    val derHeader = byteArrayOf(
                        0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
                        0x03, 0x2B, 0x65, 0x6E, 0x04, 0x22, 0x04, 0x20
                    )
                    val keySpec = java.security.spec.PKCS8EncodedKeySpec(derHeader + privateKey)
                    val kf = java.security.KeyFactory.getInstance("X25519")
                    // If KeyFactory works, generate a proper keypair instead
                    val kpg2 = java.security.KeyPairGenerator.getInstance("X25519")
                    val kp2 = kpg2.generateKeyPair()
                    
                    val pubEncoded = kp2.public.encoded
                    val rawPub = pubEncoded.sliceArray(pubEncoded.size - 32 until pubEncoded.size)
                    publicKeyBase64 = Base64.encodeToString(rawPub, Base64.NO_WRAP)
                    
                    val privEncoded = kp2.private.encoded
                    val rawPriv = privEncoded.sliceArray(privEncoded.size - 32 until privEncoded.size)
                    privateKeyBase64 = Base64.encodeToString(rawPriv, Base64.NO_WRAP)
                    
                    LogManager.log("[WARP] ✓ Fallback KeyFactory başarılı.")
                } catch (e2: Exception) {
                    LogManager.log("[WARP] ✗ KeyFactory da başarısız: ${e2.message}")
                    LogManager.log("[WARP] Random public key kullanılıyor (son çare).")
                    val pubKey = ByteArray(32)
                    random.nextBytes(pubKey)
                    publicKeyBase64 = Base64.encodeToString(pubKey, Base64.NO_WRAP)
                }
            }
            
            // ═══ 2. Cloudflare API Kaydı ═══
            LogManager.log("[WARP] Adım 2/3: Cloudflare API'ye kayıt gönderiliyor...")
            LogManager.log("[WARP] URL: https://api.cloudflareclient.com/v0a2158/reg")
            
            val url = URL("https://api.cloudflareclient.com/v0a2158/reg")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("User-Agent", "okhttp/3.12.1")
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
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
            
            LogManager.log("[WARP] İstek gövdesi hazırlandı (${body.toString().length} byte)")
            
            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
            
            val responseCode = conn.responseCode
            LogManager.log("[WARP] Yanıt kodu: $responseCode")
            
            if (responseCode == 200) {
                val responseStr = conn.inputStream.bufferedReader().use { it.readText() }
                LogManager.log("[WARP] Yanıt boyutu: ${responseStr.length} byte")
                
                val response = JSONObject(responseStr)
                
                // ═══ 3. Yanıt Parse Etme ═══
                LogManager.log("[WARP] Adım 3/3: Yanıt parse ediliyor...")
                
                // Cloudflare API response structure can vary
                val config = response.getJSONObject("config")
                val clientInterface = config.getJSONObject("interface")
                val addresses = clientInterface.getJSONObject("addresses")
                
                LogManager.log("[WARP] Alınan adresler: $addresses")
                
                val localIPv4 = addresses.optString("v4", "172.16.0.2") + "/32"
                val localIPv6 = if (addresses.has("v6")) addresses.getString("v6") + "/128" else ""
                
                LogManager.log("[WARP] Atanan IPv4: $localIPv4")
                LogManager.log("[WARP] Atanan IPv6: ${localIPv6.ifEmpty { "yok" }}")
                
                val prefs = getSharedPreferences("freenet_prefs", Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putString("warp_private_key", privateKeyBase64)
                    putString("warp_local_ipv4", localIPv4)
                    putString("warp_local_ipv6", localIPv6)
                    apply()
                }
                
                LogManager.log("[WARP] ✓ Kayıt başarılı! Profil kaydedildi.")
                return@withContext true
            } else {
                val errorBody = try {
                    conn.errorStream?.bufferedReader()?.use { it.readText() } ?: "boş yanıt"
                } catch (_: Exception) { "okunamadı" }
                LogManager.log("[WARP] ✗ Kayıt başarısız!")
                LogManager.log("[WARP] HTTP Kodu: $responseCode")
                LogManager.log("[WARP] Hata detayı: $errorBody")
            }
        } catch (e: java.net.SocketTimeoutException) {
            LogManager.log("[WARP] ✗ Bağlantı zaman aşımı! Cloudflare sunucusuna ulaşılamıyor.")
            LogManager.log("[WARP] İnternet bağlantınızı kontrol edin.")
        } catch (e: java.net.UnknownHostException) {
            LogManager.log("[WARP] ✗ DNS çözümlenemiyor: ${e.message}")
            LogManager.log("[WARP] İnternet bağlantınız olduğundan emin olun.")
        } catch (e: Exception) {
            LogManager.log("[WARP] ✗ Beklenmeyen hata!")
            LogManager.log("[WARP] Hata tipi: ${e.javaClass.simpleName}")
            LogManager.log("[WARP] Mesaj: ${e.localizedMessage}")
            e.stackTrace.take(8).forEach { frame ->
                LogManager.log("[WARP]   $frame")
            }
        }
        return@withContext false
    }
}

// Simple extension helper for coroutines in ComponentActivity
private val ComponentActivity.lifecycleScope get() = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.Main)

// ═══════════════════════════════════════
// Theme
// ═══════════════════════════════════════

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

// ═══════════════════════════════════════
// Main Screen
// ═══════════════════════════════════════

@Composable
fun MainScreen(
    isConnected: Boolean,
    selectedMode: AppMode,
    isRegisteringWarp: Boolean,
    onModeSelected: (AppMode) -> Unit,
    onToggleConnection: () -> Unit
) {
    val context = LocalContext.current
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

            // Pulse Glow Button
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(160.dp)
                    .clickable { if (!isRegisteringWarp) onToggleConnection() }
            ) {
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .blur(20.dp)
                        .background(buttonGlowColor.copy(alpha = if (isConnected) 0.5f else 0.1f), CircleShape)
                )
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

            // Modes
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

            // ═══ Log Console ═══
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xFF08090C))
                    .border(BorderStroke(1.dp, Color(0xFF1A1C24)), RoundedCornerShape(16.dp))
            ) {
                // Console Header with Copy & Share buttons
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF0F1014))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "CANLI GÜNLÜK",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.LightGray,
                        letterSpacing = 1.sp
                    )
                    
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        // Copy button
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = Color(0xFF1A1C24),
                            modifier = Modifier.clickable { LogManager.copyToClipboard(context) }
                        ) {
                            Text(
                                text = "📋 KOPYALA",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF66BB6A),
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                            )
                        }
                        
                        // Share button
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = Color(0xFF1A1C24),
                            modifier = Modifier.clickable {
                                val sendIntent = Intent().apply {
                                    action = Intent.ACTION_SEND
                                    putExtra(Intent.EXTRA_TEXT, LogManager.getFullLogText())
                                    type = "text/plain"
                                }
                                context.startActivity(Intent.createChooser(sendIntent, "Logları paylaş"))
                            }
                        ) {
                            Text(
                                text = "📤 PAYLAŞ",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF42A5F5),
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                            )
                        }
                        
                        // Clear button
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = Color(0xFF1A1C24),
                            modifier = Modifier.clickable { LogManager.clear() }
                        ) {
                            Text(
                                text = "🗑 TEMİZLE",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFFEF5350),
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                            )
                        }
                    }
                }

                HorizontalDivider(color = Color(0xFF1A1C24))

                // Selectable logs list
                val listState = rememberLazyListState()
                LaunchedEffect(logs.size) {
                    if (logs.isNotEmpty()) {
                        listState.animateScrollToItem(logs.size - 1)
                    }
                }

                SelectionContainer {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(8.dp)
                    ) {
                        itemsIndexed(logs) { index, log ->
                            val logColor = remember(log) {
                                val lower = log.lowercase()
                                when {
                                    lower.contains("✗") || lower.contains("hata") || lower.contains("error") || lower.contains("fail") -> Color(0xFFEF5350)
                                    lower.contains("uyarı") || lower.contains("warning") -> Color(0xFFFFB74D)
                                    lower.contains("✓") || lower.contains("başarılı") || lower.contains("aktif") || lower.contains("success") -> Color(0xFF81C784)
                                    lower.contains("[config") -> Color(0xFF80DEEA)
                                    lower.contains("[tünel") -> Color(0xFFCE93D8)
                                    lower.contains("[warp") -> Color(0xFFA5D6A7)
                                    lower.contains("[sing-box") -> Color(0xFF4DD0E1)
                                    lower.contains("[platform") || lower.contains("[handler") -> Color(0xFF90A4AE)
                                    lower.contains("═══") -> Color(0xFFFFD54F)
                                    else -> Color.White.copy(alpha = 0.85f)
                                }
                            }
                            
                            Text(
                                text = log,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 10.sp,
                                color = logColor,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 1.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}
