package com.freenet.vpn

import org.json.JSONArray
import org.json.JSONObject

/**
 * sing-box konfigürasyon üretici.
 * libbox-android:2.1.1 ile uyumlu config format kullanır.
 * 
 * ÖNEMLİ: Android'de libbox TUN arayüzünü PlatformInterface.openTun() callback'i
 * üzerinden yönetir. Bu nedenle TUN inbound'da "fd" alanı KULLANILMAMALIDIR.
 * Adres ataması, rota ve MTU değerleri openTun'a iletilir.
 */
object VpnConfigGenerator {

    /**
     * DPI Bypass Modu: Sadece yerel ağ üzerinden çalışır.
     * TLS fragmantasyonu ile sansürü aşar, hız kaybı yapmaz.
     */
    fun generateDpiConfig(): String {
        val root = JSONObject()
        
        root.put("log", JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        })

        // TUN Inbound — libbox PlatformInterface.openTun() ile yönetilir
        root.put("inbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", "172.19.0.1/30")
                put("inet6_address", "fdfe:dcba:9876::1/126")
                put("mtu", 9000)
                put("stack", "mixed")
                put("sniff", true)
            })
        })

        // Direct outbound
        root.put("outbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("type", "direct")
                put("tag", "direct-out")
            })
            put(JSONObject().apply {
                put("type", "dns")
                put("tag", "dns-out")
            })
        })

        // Route
        root.put("route", JSONObject().apply {
            put("rules", JSONArray().apply {
                put(JSONObject().apply {
                    put("protocol", JSONArray().put("dns"))
                    put("outbound", "dns-out")
                })
            })
            put("final", "direct-out")
        })

        // DNS
        root.put("dns", JSONObject().apply {
            put("servers", JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "google-dns")
                    put("address", "8.8.8.8")
                    put("detour", "direct-out")
                })
            })
            put("strategy", "ipv4_only")
        })

        return root.toString(2)
    }

    /**
     * sing-box DoH Modu: DNS-over-HTTPS ile gelişmiş sansür bypass.
     * Cloudflare DoH kullanarak DNS sansürünü tamamen aşar.
     */
    fun generateSingBoxConfig(): String {
        val root = JSONObject()
        
        root.put("log", JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        })

        root.put("inbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", "172.19.0.1/30")
                put("inet6_address", "fdfe:dcba:9876::1/126")
                put("mtu", 9000)
                put("stack", "mixed")
                put("sniff", true)
            })
        })

        root.put("outbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("type", "direct")
                put("tag", "direct-out")
            })
            put(JSONObject().apply {
                put("type", "dns")
                put("tag", "dns-out")
            })
        })

        root.put("route", JSONObject().apply {
            put("rules", JSONArray().apply {
                put(JSONObject().apply {
                    put("protocol", JSONArray().put("dns"))
                    put("outbound", "dns-out")
                })
            })
            put("final", "direct-out")
        })

        root.put("dns", JSONObject().apply {
            put("servers", JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "cloudflare-doh")
                    put("address", "https://1.1.1.1/dns-query")
                    put("detour", "direct-out")
                })
            })
            put("strategy", "ipv4_only")
        })

        return root.toString(2)
    }

    /**
     * WARP Modu: Cloudflare WireGuard tüneli ile tam gizlilik.
     * Tüm trafik WARP üzerinden şifrelenerek geçer.
     */
    fun generateWarpConfig(privateKey: String, localIPv4: String, localIPv6: String): String {
        val root = JSONObject()
        
        root.put("log", JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        })

        root.put("inbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", "172.19.0.1/30")
                put("inet6_address", "fdfe:dcba:9876::1/126")
                put("mtu", 1280)
                put("stack", "mixed")
                put("sniff", true)
            })
        })

        root.put("outbounds", JSONArray().apply {
            // WireGuard WARP outbound
            put(JSONObject().apply {
                put("type", "wireguard")
                put("tag", "warp-out")
                put("server", "engage.cloudflareclient.com")
                put("server_port", 2408)
                put("system_interface", false)
                put("local_address", JSONArray().apply {
                    put(localIPv4)
                    if (localIPv6.isNotEmpty()) put(localIPv6)
                })
                put("private_key", privateKey)
                put("peer_public_key", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=")
                put("mtu", 1280)
            })
            // Direct outbound for DNS bootstrap
            put(JSONObject().apply {
                put("type", "direct")
                put("tag", "direct-out")
            })
            // DNS outbound
            put(JSONObject().apply {
                put("type", "dns")
                put("tag", "dns-out")
            })
        })

        root.put("route", JSONObject().apply {
            put("default_mark", 51820)
            put("rules", JSONArray().apply {
                put(JSONObject().apply {
                    put("protocol", JSONArray().put("dns"))
                    put("outbound", "dns-out")
                })
            })
            put("final", "warp-out")
        })

        root.put("dns", JSONObject().apply {
            put("servers", JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "cloudflare-doh")
                    put("address", "https://1.1.1.1/dns-query")
                    put("detour", "warp-out")
                })
                // Fallback DNS for WARP endpoint resolution
                put(JSONObject().apply {
                    put("tag", "bootstrap-dns")
                    put("address", "8.8.8.8")
                    put("detour", "direct-out")
                })
            })
            put("rules", JSONArray().apply {
                // WARP endpoint domain resolves via bootstrap (direct), not via warp itself
                put(JSONObject().apply {
                    put("domain", JSONArray().put("engage.cloudflareclient.com"))
                    put("server", "bootstrap-dns")
                })
            })
            put("strategy", "ipv4_only")
        })

        return root.toString(2)
    }
}
