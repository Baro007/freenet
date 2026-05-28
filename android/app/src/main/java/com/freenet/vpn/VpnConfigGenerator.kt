package com.freenet.vpn

import org.json.JSONArray
import org.json.JSONObject

object VpnConfigGenerator {

    fun generateDpiConfig(fd: Int): String {
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
                put("fd", fd)
                put("auto_route", false)
                put("strict_route", false)
                put("stack", "gvisor")
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

        // Routing Rules - Sniiffing & Fragmentation
        val route = JSONObject().apply {
            val rules = JSONArray().apply {
                put(JSONObject().apply {
                    put("inbound", JSONArray().put("tun-in"))
                    put("action", "sniff")
                })
                put(JSONObject().apply {
                    put("port", JSONArray().put(443))
                    put("action", "route-options")
                    put("tls_record_fragment", true)
                })
            }
            put("rules", rules)
        }
        root.put("route", route)

        // DNS Configuration (System default)
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

    fun generateSingBoxConfig(fd: Int): String {
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
                put("fd", fd)
                put("auto_route", false)
                put("strict_route", false)
                put("stack", "gvisor")
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

        // Routing Rules - Sniffing & Fragmentation
        val route = JSONObject().apply {
            val rules = JSONArray().apply {
                put(JSONObject().apply {
                    put("inbound", JSONArray().put("tun-in"))
                    put("action", "sniff")
                })
                put(JSONObject().apply {
                    put("port", JSONArray().put(443))
                    put("action", "route-options")
                    put("tls_record_fragment", true)
                })
            }
            put("rules", rules)
        }
        root.put("route", route)

        // DNS Configuration (Cloudflare DoH)
        val dns = JSONObject().apply {
            val servers = JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "cloudflare-doh")
                    put("type", "https")
                    put("server", "1.1.1.1")
                    put("server_port", 443)
                    put("path", "/dns-query")
                })
            }
            put("servers", servers)
            put("strategy", "ipv4_only")
        }
        root.put("dns", dns)

        return root.toString(2)
    }

    fun generateWarpConfig(fd: Int, privateKey: String, localIPv4: String, localIPv6: String): String {
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
                put("fd", fd)
                put("auto_route", false)
                put("strict_route", false)
                put("stack", "gvisor")
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
        }
        root.put("outbounds", outbounds)

        // Routing Rules - All to warp-out
        val route = JSONObject().apply {
            val rules = JSONArray().apply {
                put(JSONObject().apply {
                    put("inbound", JSONArray().put("tun-in"))
                    put("action", "sniff")
                })
                put(JSONObject().apply {
                    put("outbound", "warp-out")
                })
            }
            put("rules", rules)
        }
        root.put("route", route)

        // DNS Configuration (Cloudflare DoH detoured to warp-out)
        val dns = JSONObject().apply {
            val servers = JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "cloudflare-doh")
                    put("type", "https")
                    put("server", "1.1.1.1")
                    put("server_port", 443)
                    put("path", "/dns-query")
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
