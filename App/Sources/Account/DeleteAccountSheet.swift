//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  DeleteAccountSheet.swift — confirmation for irreversible account deletion.
//
//  App Store Review Guideline 5.1.1(v): an app that lets people create an
//  account must let them delete it from inside the app. This is that path — the
//  portal's own delete page is the web half, and both call `DELETE /api/me`.
//
//  The confirmation asks you to type your own address rather than tick a box or
//  tap twice, matching Android and the portal. There is no undo and no grace
//  period, so the gesture should be hard to make by accident — and typing the
//  address also proves you know whose account you are looking at, which matters
//  on a device someone else may have signed in on.
//
import SwiftUI

struct DeleteAccountSheet: View {
    let email: String
    let busy: Bool
    let error: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var typed = ""

    /// Normally the account's address. If the stored email is somehow missing
    /// we must not fall through to "empty input matches empty target" — nor
    /// lock the user out of a flow Apple requires to work — so fall back to a
    /// literal word.
    private var target: String {
        email.isEmpty ? "DELETE" : email
    }

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(target) == .orderedSame
    }

    var body: some View {
        // See RegionPickerView: `.presentationBackground` is iOS 16.4 and this
        // app deploys to 16.0, so the ground is painted behind the content.
        ZStack {
            Theme.ground2.ignoresSafeArea()
            content
        }
        .presentationDetents([.medium])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Delete account")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("This deletes your account, every device on it, and the keys that connect them. Any tunnel that is up will be cut. It happens immediately and cannot be undone.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)

            Text(email.isEmpty ? "Type DELETE to confirm." : "Type \(target) to confirm.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(.top, 12)

            TextField("", text: $typed)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(email.isEmpty ? .default : .emailAddress)
                .submitLabel(.done)
                .disabled(busy)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(matches ? Theme.rose : Theme.stroke, lineWidth: 1)
                )
                .padding(.top, 10)

            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.rose)
                    .padding(.top, 10)
            }

            HStack(spacing: 12) {
                GlassButton(title: "Cancel") {
                    if !busy { onCancel() }
                }

                Button(action: onConfirm) {
                    Group {
                        if busy {
                            ProgressView().tint(Theme.rose)
                        } else {
                            Text("Delete permanently")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(matches ? Theme.rose : Theme.faint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Theme.rose.opacity(matches ? 0.12 : 0.04),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(
                                matches ? Theme.rose.opacity(0.45) : Theme.stroke,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!matches || busy)
            }
            .padding(.top, 22)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
