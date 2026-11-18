import Foundation

// Pure-logic tests calling SHIPPED IntentEngineMapper, DPIArgsValidator, ChecksumVerifier.

@main
struct LogicTestsMain {
    static var failures = 0

    static func expect(_ cond: Bool, _ msg: String) {
        if cond {
            print("  PASS: \(msg)")
        } else {
            print("  FAIL: \(msg)")
            failures += 1
        }
    }

    static func testIntentMapping() {
        print("== IntentEngineMapper ==")

        let bal = IntentEngineMapper.primaryEngine(intent: .balanced, fastPreference: .auto)
        expect(bal == .warp, "balanced → warp (got \(bal))")

        let priv = IntentEngineMapper.primaryEngine(intent: .maxPrivacy, fastPreference: .auto)
        expect(priv == .tor, "maxPrivacy → tor (got \(priv))")

        let fastSB = IntentEngineMapper.primaryEngine(intent: .fast, fastPreference: .singbox)
        expect(fastSB == .singbox, "fast+singbox → singbox")

        let fastDPI = IntentEngineMapper.primaryEngine(intent: .fast, fastPreference: .dpi)
        expect(fastDPI == .dpi, "fast+dpi → dpi")

        let fastAuto = IntentEngineMapper.primaryEngine(intent: .fast, fastPreference: .auto)
        expect(fastAuto == .singbox, "fast+auto primary → singbox (first-class)")

        let autoCand = IntentEngineMapper.engineCandidates(intent: .fast, fastPreference: .auto)
        expect(autoCand == [.singbox, .dpi], "auto candidates [singbox, dpi] got \(autoCand)")

        let sbOnly = IntentEngineMapper.engineCandidates(intent: .fast, fastPreference: .singbox)
        expect(sbOnly == [.singbox], "singbox-only candidates")

        expect(IntentMode.maxPrivacy.showsSlownessWarning == true, "max privacy shows slowness warning")
        expect(IntentMode.fast.showsSlownessWarning == false, "fast no slowness warning")
        expect(IntentMode.maxPrivacy.privacyLevel == .anonymity, "max privacy anonymity level")
        expect(IntentMode.balanced.privacyLevel == .ipMask, "balanced ipMask")
    }

    static func testDPIValidation() {
        print("== DPIArgsValidator ==")

        let good = DPIArgsValidator.validate("-d 1 -p 1080")
        expect(good.isValid, "default-like args valid")
        expect(good.port == 1080, "port 1080")
        expect(good.arguments == ["-d", "1", "-p", "1080"], "tokens exact \(good.arguments)")

        let inject = DPIArgsValidator.validate("-d 1; rm -rf /")
        expect(!inject.isValid, "shell metachar rejected")

        let badFlag = DPIArgsValidator.validate("-z 1")
        expect(!badFlag.isValid, "unknown flag rejected")

        let badPort = DPIArgsValidator.validate("-p 80")
        expect(!badPort.isValid, "privileged port rejected")

        let empty = DPIArgsValidator.validate("")
        expect(empty.isValid, "empty falls back to default")
        expect(empty.port == 1080, "empty default port")

        let dollar = DPIArgsValidator.validate("-d 1 -p $(whoami)")
        expect(!dollar.isValid, "command sub rejected")

        let def = DPIArgsValidator.validate(DPIArgsValidator.defaultArgs)
        expect(def.isValid, "hardened default args valid (\(def.errorMessage ?? "ok"))")
        expect(def.port == 1080, "hardened default port 1080")
        expect(def.arguments.contains("-i") && def.arguments.contains("127.0.0.1"), "hardened default binds localhost only")
        expect(def.arguments.contains("1+s"), "hardened default supports SNI offset 1+s")
        expect(def.arguments.contains("-A"), "hardened default includes auto fallback")
    }

    static func testSingBoxConfig() {
        print("== SingBoxConfig ==")
        let recJSON = SingBoxConfig.makeJSON(listenPort: 1081, fragmentMode: .recordFragment, dnsProfile: .cloudflareSecurity)
        let recObj = (try? JSONSerialization.jsonObject(with: recJSON.data(using: .utf8)!)) as? [String: Any]
        expect(recObj != nil, "recordFragment produces valid JSON")
        expect(recJSON.contains("\"type\": \"mixed\""), "uses mixed inbound (SOCKS5 + HTTP)")
        expect(recJSON.contains("\"reuse_addr\": true"), "sets reuse_addr")
        expect(recJSON.contains("\"default_domain_resolver\""), "sets default_domain_resolver")
        expect(recJSON.contains("\"1.1.1.2\""), "uses selected DoH IP 1.1.1.2")
        expect(recJSON.contains("\"cache_capacity\": 4096"), "sets 4096 DNS cache")
        expect(recJSON.contains("\"HTTPS\", \"SVCB\""), "strips HTTPS/SVCB DNS records (anti-QUIC)")
        expect(recJSON.contains("\"hijack-dns\""), "hijacks plaintext DNS on port 53")
        expect(recJSON.contains("195.175.254.2/32"), "blocks BTK sinkhole IP")
        expect(recJSON.contains("0.0.0.0/8"), "cleanly rejects DNS ad/malware sinkhole 0.0.0.0/8")
        expect(recJSON.contains("\".test\""), "bypasses .test local DNS")
        expect(recJSON.contains("\"protocol\": \"quic\""), "rejects QUIC for instant TCP fallback")
        expect(recJSON.contains("\"ip_is_private\": true"), "bypasses private/LAN IPs")
        expect(recJSON.contains("\"tls_record_fragment\": true"), "record mode sets tls_record_fragment")
        expect(!recJSON.contains("\"tls_fragment\": true"), "record mode does not mix mutually-exclusive tls_fragment")

        let tcpJSON = SingBoxConfig.makeJSON(listenPort: 1081, fragmentMode: .tcpFragment, dnsProfile: .adguardShield)
        let tcpObj = (try? JSONSerialization.jsonObject(with: tcpJSON.data(using: .utf8)!)) as? [String: Any]
        expect(tcpObj != nil, "tcpFragment produces valid JSON")
        expect(tcpJSON.contains("\"94.140.14.14\""), "uses AdGuard DoH IP 94.140.14.14")
        expect(tcpJSON.contains("\"tls_fragment\": true"), "tcp mode sets tls_fragment")
        expect(!tcpJSON.contains("\"tls_record_fragment\": true"), "tcp mode does not mix mutually-exclusive tls_record_fragment")

        let hybJSON = SingBoxConfig.makeJSON(listenPort: 1081, fragmentMode: .hybridShield, dnsProfile: .quad9Security, ciadpiPort: 1082)
        let hybObj = (try? JSONSerialization.jsonObject(with: hybJSON.data(using: .utf8)!)) as? [String: Any]
        expect(hybObj != nil, "hybridShield produces valid JSON")
        expect(hybJSON.contains("\"9.9.9.9\""), "uses Quad9 DoH IP 9.9.9.9")
        expect(hybJSON.contains("\"tag\": \"ciadpi-out\""), "hybrid mode includes ciadpi-out outbound")
        expect(hybJSON.contains("\"server_port\": 1082"), "hybrid mode targets internal ciadpi port 1082")
        expect(hybJSON.contains("\"protocol\": [\"tls\", \"http\"]"), "hybrid mode protects both TLS and HTTP:80")

        let failover = SingBoxDNSProfile.adguardShield.failoverCandidates
        expect(failover.first == .adguardShield, "failover starts with preferred profile")
        expect(failover.count == 5, "failover includes all 5 unique DoH profiles (got \(failover.count))")
    }

    static func testWarpConfigOptimizer() {
        print("== WarpConfigOptimizer ==")
        let sample = """
        [Interface]
        PrivateKey = TEST_PRIV_KEY
        Address = 172.16.0.2/32, 2606:4700:110::1/128
        DNS = 1.1.1.1, 1.0.0.1
        MTU = 1280
        [Peer]
        PublicKey = TEST_PUB_KEY
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = engage.cloudflareclient.com:2408
        """
        let opt = WarpConfigOptimizer.optimize(sample, port: 500, mtu: 1380, keepalive: 25)
        expect(opt.contains("MTU = 1380"), "MTU upgraded to 1380")
        expect(!opt.contains("MTU = 1280"), "old MTU 1280 replaced")
        expect(opt.contains("Endpoint = engage.cloudflareclient.com:500"), "Endpoint port switched to 500")
        expect(opt.contains("PersistentKeepalive = 25"), "PersistentKeepalive added")
        expect(opt.contains("PrivateKey = TEST_PRIV_KEY"), "PrivateKey preserved")
        expect(opt.contains("AllowedIPs = 0.0.0.0/0, ::/0"), "AllowedIPs IPv4+IPv6 preserved")

        let opt2 = WarpConfigOptimizer.optimize(opt, port: 500, mtu: 1380, keepalive: 25)
        expect(opt == opt2, "optimizer is idempotent")

        let optDNS = WarpConfigOptimizer.optimize(
            sample,
            port: 500,
            endpointHost: "162.159.193.1",
            dnsProfile: .adguardShield
        )
        expect(optDNS.contains("Endpoint = 162.159.193.1:500"), "alternate WARP host + port applied")
        expect(optDNS.contains("DNS = 94.140.14.14, 94.140.15.15"), "DNS profile aligned in wgcf.conf")

        let parsed = WgcfConfigParser.parse(sample)
        expect(parsed != nil, "WgcfConfigParser parses standard wgcf.conf")
        expect(parsed?.privateKey == "TEST_PRIV_KEY", "parsed PrivateKey exact")
        expect(parsed?.publicKey == "TEST_PUB_KEY", "parsed PublicKey exact")
        expect(parsed?.addresses.count == 2, "parsed IPv4 + IPv6 addresses")
        expect(parsed?.endpointPort == 2408, "parsed endpoint port 2408")

        let targets = WgcfConfigParser.failoverTargets(preferredPort: 500)
        expect(targets.first == WarpEndpointTarget(host: "162.159.193.1", port: 500), "failover starts with 162.159.193.1:500")
        expect(targets.contains(WarpEndpointTarget(host: "162.159.192.1", port: 2408)), "failover includes fallback 2408")

        if let p = parsed {
            let sbWarpJSON = SingBoxWarpConfig.makeJSON(
                wgcf: p,
                endpoint: targets[0],
                listenPort: 1083,
                dnsProfile: .adguardShield
            )
            let obj = (try? JSONSerialization.jsonObject(with: sbWarpJSON.data(using: .utf8)!)) as? [String: Any]
            expect(obj != nil, "SingBoxWarpConfig produces valid JSON")
            expect(sbWarpJSON.contains("\"type\": \"wireguard\""), "contains wireguard endpoint")
            expect(sbWarpJSON.contains("\"detour\": \"warp-ep\""), "routes DoH inside WARP tunnel")
            expect(sbWarpJSON.contains("\"94.140.14.14\""), "applies AdGuard DoH inside WARP")
            expect(sbWarpJSON.contains("\"162.159.193.1\""), "uses IP-literal endpoint (zero bootstrap deadlock)")
            expect(sbWarpJSON.contains("\"listen_port\": 1083"), "listens on dedicated port 1083")
            expect(sbWarpJSON.contains("\"persistent_keepalive_interval\": 25"), "sets keepalive 25s")
        }
    }

    static func testChecksum() {
        print("== ChecksumVerifier ==")

        let sample = """
        # comment
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  empty.bin
        deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef *other
        """
        let entries = ChecksumVerifier.parseChecksumFile(sample)
        expect(entries.count == 2, "parsed 2 entries got \(entries.count)")
        expect(entries[0].filename == "empty.bin", "filename empty.bin")
        expect(entries[0].hash.count == 64, "hash length 64")

        let data = Data()
        let hex = ChecksumVerifier.sha256Hex(of: data)
        expect(hex == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty SHA-256")

        let tmp = NSTemporaryDirectory() + "freenet-test-\(UUID().uuidString)"
        let binPath = tmp + "/empty.bin"
        let sumPath = tmp + "/CHECKSUMS.sha256"
        try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        try! Data().write(to: URL(fileURLWithPath: binPath))
        try! "\(hex)  empty.bin\n".write(toFile: sumPath, atomically: true, encoding: .utf8)

        let status = ChecksumVerifier.verify(binaryPath: binPath, checksumFilePath: sumPath)
        expect(status == .match, "file verify match")

        let safe = ChecksumVerifier.assertSafeToRun(binaryPath: binPath, checksumFilePath: sumPath)
        expect(safe.ok, "assertSafeToRun ok")

        try! "0000000000000000000000000000000000000000000000000000000000000000  empty.bin\n"
            .write(toFile: sumPath, atomically: true, encoding: .utf8)
        let bad = ChecksumVerifier.assertSafeToRun(binaryPath: binPath, checksumFilePath: sumPath)
        expect(!bad.ok, "mismatch not safe")

        try? FileManager.default.removeItem(atPath: tmp)
    }

    static func testTorReadiness() {
        print("== TorReadiness ==")
        let tmp = NSTemporaryDirectory() + "freenet-tor-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        // Force no system candidates so test is hermetic
        let missing = TorReadiness.missingBinaryMessage(binDir: tmp, systemCandidates: [])
        expect(missing != nil, "missing tor yields message")
        expect(missing == TorReadiness.missingMessage, "exact missing message")
        // create fake tor file
        let torPath = (tmp as NSString).appendingPathComponent("tor")
        try! Data([0x00]).write(to: URL(fileURLWithPath: torPath))
        let present = TorReadiness.missingBinaryMessage(binDir: tmp, systemCandidates: [])
        expect(present == nil, "present tor yields nil missing message")
        // system candidate path
        let viaSystem = TorReadiness.missingBinaryMessage(binDir: tmp + "-empty", systemCandidates: [torPath])
        expect(viaSystem == nil, "system candidate satisfies readiness")
        try? FileManager.default.removeItem(atPath: tmp)
    }

    static func testAppVersion() {
        print("== AppVersion ==")
        expect(AppVersion.isRemoteNewer("1.2.0", than: "1.1.0"), "1.2.0 > 1.1.0")
        expect(!AppVersion.isRemoteNewer("1.1.0", than: "1.1.0"), "same not newer")
        expect(!AppVersion.isRemoteNewer("1.0.9", than: "1.1.0"), "older not newer")
        expect(AppVersion.isRemoteNewer("v2.0.0", than: "1.9.9"), "v prefix ok")
        let parsed = AppVersion.parseVERSIONFile("1.2.3\n")
        expect(parsed?.version == "1.2.3", "plain VERSION parse")
        let json = AppVersion.parseVERSIONFile("{\"version\":\"2.0.0\",\"notes\":\"hi\",\"url\":\"https://example.com\"}")
        expect(json?.version == "2.0.0", "json VERSION parse")
        expect(json?.notes == "hi", "json notes")
    }

    static func main() {
        print("Freenet logic tests (shipped sources)")
        testIntentMapping()
        testDPIValidation()
        testSingBoxConfig()
        testWarpConfigOptimizer()
        testChecksum()
        testTorReadiness()
        testAppVersion()
        print("----")
        if failures == 0 {
            print("ALL PASSED")
            exit(0)
        } else {
            print("FAILURES: \(failures)")
            exit(1)
        }
    }
}
