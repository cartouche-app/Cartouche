//
//  GallerySMB.swift
//  CartoucheGallery
//
//  Add a shared folder (-GalleryScreen storage-smb) with a NAS nearby that
//  refused the sign-in which lists its shared folders (-GalleryWork
//  smb-refused or smb-no-guests): in the gallery, the SMB browser never
//  looks at the network it runs on (CartoucheSMBBrowser.gallery).
//

import Foundation

/// A NAS of the house on Add a shared folder (screen storage-smb), found
/// nearby, which refused the sign-in that lists its shared folders: the
/// user name or the password the player typed (work: smb-refused), or a
/// guest, without a user name (smb-no-guests). Made-up name, address and
/// account.
enum GallerySMB {
    static let nearby = [CartoucheSMBBrowser.Server(name: "NAS", host: "nas.local")]

    /// The server as the player typed it for WORK: the NAS chosen nearby,
    /// with their user name, or none.
    static func server(_ work: String?) -> CartoucheStorageServer {
        CartoucheStorageServer(kind: .smb, name: "NAS", host: "nas.local", username: work == "smb-no-guests" ? "" : "joueur",
                               share: "")
    }

    /// The password typed for WORK, and what the form says once the NAS
    /// answered the sign-in with STATUS_LOGON_FAILURE, as Samba, Windows and
    /// macOS answer a wrong password, an unknown user and a guest they do
    /// not let in (CartoucheSMBRefusal).
    @MainActor
    static func signIn(_ work: String?) -> (password: String, problem: CartoucheReport?) {
        let nas = server(work)
        let guest = nas.username.isEmpty
        guard let reason = CartoucheSMBRefusal.reason(0xC000_006D, guest: guest) else {
            return (password: "", problem: nil)
        }
        let error = CartoucheStorageError(.signInFailed, CartoucheText.storageSignInFailed(nas.host, reason))
        return (password: guest ? "" : "motdepasse", problem: CartoucheReports.connectionFailed(to: nas, error: error))
    }
}
