//
//  PacketTunnelProvider.swift — the WireGuard tunnel runs in this app extension.
//
//  P3. Replaces the P0 stub, which satisfied the NEPacketTunnelProvider
//  contract and did nothing: `startTunnel` called back with success while no
//  tunnel existed, so the system showed "Connected" over a dead interface.
//
//  The extension is a separate process with a tight memory budget, started by
//  the system rather than by the app. Two consequences shape everything here:
//  it cannot ask the app for anything at startup, so its whole configuration
//  must already be inside `providerConfiguration`; and an uncaught trap reads
//  to the user as the VPN switching itself off, with no error to look at. So
//  every failure below is returned, never forced.
//
import NetworkExtension
import os
import WireGuardKit

final class PacketTunnelProvider: NEPacketTunnelProvider {

    enum TunnelError: LocalizedError {
        case missingConfiguration
        case invalidConfiguration

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Tidak ada konfigurasi tunnel yang tersimpan untuk profil ini."
            case .invalidConfiguration:
                return "Konfigurasi tunnel tersimpan tetapi tidak bisa dibaca."
            }
        }
    }

    private static let log = Logger(subsystem: "com.avangard.vpn.network-extension", category: "tunnel")

    /*
      Lazy because WireGuardAdapter takes `self`, and a stored property cannot
      reference self during initialisation. The adapter owns the wireguard-go
      backend and the utun file descriptor for the life of the extension
      process, so there is exactly one and it is never replaced.
    */
    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { level, message in
            /*
              WireGuardKit has two levels, and neither is `debug`. Mapping
              `.verbose` to `.debug` keeps the handshake chatter out of the
              default log while leaving errors visible in Console.app without
              attaching a debugger — which matters because the usual way to
              watch this code run is on a phone that is not plugged in.

              privacy: .public because the backend's own messages carry no
              secrets: keys are never logged, endpoints are already visible to
              anyone watching the network. Without it every line renders as
              <private> and the log stops being worth reading.
            */
            switch level {
            case .error:
                Self.log.error("\(message, privacy: .public)")
            case .verbose:
                Self.log.debug("\(message, privacy: .public)")
            }
        }
    }()

    override func startTunnel(
        options _: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        /*
          The configuration comes from the saved VPN profile, not from `options`
          and not from the App Group. `options` is nil whenever the system
          starts the tunnel on its own — on-demand, or after a reboot — so
          anything read from it would work when the user taps Connect and fail
          silently the rest of the time. The App Group would work, but it adds
          a second place the truth can live; the profile is the one the system
          already persists and hands us.
        */
        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let stored = proto.providerConfiguration,
            let profile = TunnelProfile(providerConfiguration: stored)
        else {
            Self.log.error("startTunnel: providerConfiguration missing or unreadable")
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        guard let configuration = profile.wireGuardConfiguration else {
            Self.log.error("startTunnel: profile present but not valid WireGuard configuration")
            completionHandler(TunnelError.invalidConfiguration)
            return
        }

        Self.log.log("startTunnel: starting backend \(WireGuardAdapter.backendVersion, privacy: .public)")

        adapter.start(tunnelConfiguration: configuration) { error in
            if let error {
                Self.log.error("startTunnel: adapter refused to start — \(String(describing: error), privacy: .public)")
                completionHandler(error)
                return
            }
            Self.log.log("startTunnel: up on \(self.adapter.interfaceName ?? "?", privacy: .public)")
            completionHandler(nil)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        Self.log.log("stopTunnel: reason \(reason.rawValue, privacy: .public)")

        /*
          The completion handler runs whether or not the adapter reported an
          error. Refusing to complete a stop does not keep the tunnel alive —
          the system tears the process down regardless — it only delays that
          and can leave the UI showing "Disconnecting" until it times out.
        */
        adapter.stop { error in
            if let error {
                Self.log.error("stopTunnel: \(String(describing: error), privacy: .public)")
            }
            completionHandler()
        }
    }

    /*
      The app's only channel into this process while it is running. Answers with
      the backend's own runtime configuration — the same text `wg show` would
      print — which is where the live handshake time and byte counters come
      from. Nothing else in the app depends on it yet; it is here because the
      alternative when we do need it is shipping an extension update.
    */
    override func handleAppMessage(
        _: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        guard let completionHandler else { return }
        adapter.getRuntimeConfiguration { settings in
            completionHandler(settings?.data(using: .utf8))
        }
    }
}
