//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  LegalUrls.swift — the public legal pages, ported from Android's util/LegalUrls.kt.
//
//  Derived from the API host so a DEBUG build pointed at a local backend links
//  to that backend rather than to production.
//
//  App Store Review requires a privacy policy link in App Store Connect *and*
//  one reachable inside the app. The Account screen's Legal card is the in-app
//  half — do not drop it.
//
import Foundation

enum LegalUrls {
    static var privacy: URL { AppConfig.baseURL.appendingPathComponent("privacy") }
    static var terms: URL { AppConfig.baseURL.appendingPathComponent("terms") }
}
