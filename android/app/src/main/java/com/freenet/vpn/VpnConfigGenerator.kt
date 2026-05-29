package com.freenet.vpn

import org.json.JSONArray
import org.json.JSONObject

object VpnConfigGenerator {

    fun generateDpiConfig(): String {
        val root = JSONObject()
        
        // Log Configuration
        val log = JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        }
        root.put("log", log)

        // Inbounds - TUN (libbox manages the fd via PlatformInterface.openTun)
        val inbounds = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", "172.19.0.1/30")
                put("inet6_address", "fdfe:dcba:9876::1/126")
                put("mtu", 9000)
                put("stack", "mixed")
                put("sniff", true)
            })
        }
        root.put("inbounds", inbounds)

        // Outbounds - Direct with TLS record fragmentation
        val outbounds = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "direct")
                put("tag", "direct-out")
                put("tcp_multi_path", false)
            })
        }
        root.put("outbounds", outbounds)

        // DNS Configuration (Google DNS via direct)
        val dns = JSONObject().apply {
            val servers = JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "system-dns")
                    put("address", "8.8.8.8")
                    put("detour", "direct-out")
                })
            }
            put("servers", servers)
            put("strategy", "ipv4_only")
        }
        root.put("dns", dns)

        return root.toString(2)
    }

    fun generateSingBoxConfig(): String {
        val root = JSONObject()
        
        // Log Configuration
        val log = JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        }
        root.put("log", log)

        // Inbounds - TUN
        val inbounds = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", "172.19.0.1/30")
                put("inet6_address", "fdfe:dcba:9876::1/126")
                put("mtu", 9000)
                put("stack", "mixed")
                put("sniff", true)
            })
        }
        root.put("inbounds", inbounds)

        // Outbounds - Direct
        val outbounds = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "direct")
                put("tag", "direct-out")
            })
        }
        root.put("outbounds", outbounds)

        // DNS Configuration (Cloudflare DoH)
        val dns = JSONObject().apply {
            val servers = JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "cloudflare-doh")
                    put("address", "https://1.1.1.1/dns-query")
                    put("detour", "direct-out")
                })
            }
            put("servers", servers)
            put("strategy", "ipv4_only")
        }
        root.put("dns", dns)

        return root.toString(2)
    }

    fun generateWarpConfig(privateKey: String, localIPv4: String, localIPv6: String): String {
        val root = JSONObject()
        
        // Log Configuration
        val log = JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        }
        root.put("log", log)

        // Inbounds - TUN
        val inbounds = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", "172.19.0.1/30")
                put("inet6_address", "fdfe:dcba:9876::1/126")
                put("mtu", 1280)
                put("stack", "mixed")
                put("sniff", true)
            })
        }
        root.put("inbounds", inbounds)

        // Outbounds - WireGuard (WARP)
        val outbounds = JSONArray().apply {
            put(JSONObject().apply {
                put("type", "wireguard")
                put("tag", "warp-out")
                put("server", "engage.cloudflareclient.com")
                put("server_port", 2408)
                put("system_interface", false)
                
                val localAddress = JSONArray().apply {
                    put(localIPv4)
                    if (localIPv6.isNotEmpty()) {
                        put(localIPv6)
                    }
                }
                put("local_address", localAddress)
                put("private_key", privateKey)
                put("peer_public_key", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=")
                put("mtu", 1280)
            })
            put(JSONObject().apply {
                put("type", "direct")
                put("tag", "direct-out")
            })
        }
        root.put("outbounds", outbounds)

        // Route - default all to warp
        val route = JSONObject().apply {
            put("default_mark", 51820)
            val rules = JSONArray().apply {
                // DNS hijack
                put(JSONObject().apply {
                    put("protocol", JSONArray().put("dns"))
                    put("outbound", "dns-out")
                })
            }
            put("rules", rules)
            put("final", "warp-out")
        }
        root.put("route", route)

        // Add dns-out outbound
        val existingOutbounds = root.getJSONArray("outbounds")
        existingOutbounds.put(JSONObject().apply {
            put("type", "dns")
            put("tag", "dns-out")
        })

        // DNS Configuration (Cloudflare DoH via warp)
        val dns = JSONObject().apply {
            val servers = JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "cloudflare-doh")
                    put("address", "https://1.1.1.1/dns-query")
                    put("detour", "warp-out")
                })
            }
            put("servers", servers)
            put("strategy", "ipv4_only")
        }
        root.put("dns", dns)

        return root.toString(2)
    }
}
