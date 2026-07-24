//
//  PacketTunnelProvider.swift — the WireGuard tunnel runs in this app extension.
//
//  P0 stub: satisfies the NEPacketTunnelProvider contract so the two-target VPN
//  project compiles. P3 wires WireGuardKit here — parse the config the app passes
//  via the tunnel provider protocol (App Group / provider configuration) and drive
//  the wireguard-go adapter.
//
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // P3: build a WireGuard config from the provider configuration and start
        // the WireGuardKit adapter, then call completionHandler(nil) on success.
        completionHandler(nil)
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }
}
